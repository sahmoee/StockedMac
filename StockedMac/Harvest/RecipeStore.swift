import Foundation

actor RecipeStore {
    private let fileURL: URL
    private var recipes: [RecipeDraft] = []
    private var loaded = false

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func all() throws -> [RecipeDraft] {
        try loadIfNeeded()
        return recipes.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Recurring invariant sweep. Harvester records are imports by definition, so an
    /// absent local image makes the record invalid regardless of review state or batch.
    @discardableResult
    func purgeImageLessImports() throws -> Set<UUID> {
        try loadIfNeeded()
        let removedIDs = Set(recipes.filter { $0.image?.hasLocalFile != true }.map(\.id))
        recipes.removeAll { $0.image?.hasLocalFile != true }
        if !removedIDs.isEmpty { try persist() }
        return removedIDs
    }

    func count() throws -> Int {
        try loadIfNeeded()
        return recipes.count
    }

    func recipe(id: UUID) throws -> RecipeDraft? {
        try loadIfNeeded()
        return recipes.first { $0.id == id }
    }

    func recipes(in state: ReviewState) throws -> [RecipeDraft] {
        try loadIfNeeded()
        return recipes
            .filter { $0.reviewState == state }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Normalised source URLs already in the library, used to keep discovery
    /// from spending its request budget re-checking pages we already hold.
    func knownSourceURLs() throws -> Set<String> {
        try loadIfNeeded()
        var values = Set<String>()
        for recipe in recipes {
            if let url = recipe.source.url.nilIfBlank,
               let parsed = try? URLSafety.validatedRemoteURL(url) {
                values.insert(URLSafety.normalized(parsed).absoluteString)
            }
            if let canonical = recipe.source.canonicalURL?.nilIfBlank,
               let parsed = try? URLSafety.validatedRemoteURL(canonical) {
                values.insert(URLSafety.normalized(parsed).absoluteString)
            }
        }
        return values
    }

    func contains(sourceFingerprint: String) throws -> Bool {
        try loadIfNeeded()
        guard !sourceFingerprint.isEmpty else { return false }
        return recipes.contains { $0.sourceFingerprint == sourceFingerprint }
    }

    @discardableResult
    func upsert(_ incoming: RecipeDraft) throws -> RecipeDraft {
        let recipe = try merge(incoming)
        try persist()
        return recipe
    }

    /// Merges one draft into the in-memory array without touching disk.
    ///
    /// Split out from `upsert` so a batch can pay for exactly one file write instead of
    /// one per recipe. Writing the whole library per item made importing M recipes into a
    /// library of N cost N×M encodes — the same runaway-write problem the phone already
    /// fixed in RecipeDatabase.
    @discardableResult
    private func merge(_ incoming: RecipeDraft) throws -> RecipeDraft {
        try loadIfNeeded()
        var recipe = incoming
        guard recipe.image?.hasLocalFile == true else {
            throw CompanionError.persistence("Recipe not imported because it has no usable image.")
        }
        recipe.categories = enrichedCategories(for: recipe)
        recipe.refreshFingerprint()

        let index = recipes.firstIndex { $0.id == recipe.id }
            ?? recipes.firstIndex {
                !recipe.sourceFingerprint.isEmpty &&
                    $0.sourceFingerprint == recipe.sourceFingerprint
            }
            ?? recipes.firstIndex {
                guard let fingerprint = recipe.contentFingerprint, !fingerprint.isEmpty else { return false }
                return $0.contentFingerprint == fingerprint
            }

        if let index {
            let existing = recipes[index]
            recipe.id = existing.id
            recipe.createdAt = existing.createdAt
            // Re-importing must not silently undo a reviewer's decision.
            if existing.reviewState != .needsReview, incoming.reviewState == .needsReview {
                recipe.reviewState = existing.reviewState
            }
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        return recipe
    }

    @discardableResult
    func upsert(all incoming: [RecipeDraft]) throws -> [RecipeDraft] {
        guard !incoming.isEmpty else { return [] }
        var saved: [RecipeDraft] = []
        saved.reserveCapacity(incoming.count)
        for recipe in incoming {
            saved.append(try merge(recipe))
        }
        try persist()
        return saved
    }

    func delete(id: UUID) throws {
        try loadIfNeeded()
        recipes.removeAll { $0.id == id }
        try persist()
    }

    func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try loadIfNeeded()
        recipes.removeAll { ids.contains($0.id) }
        try persist()
    }

    /// Applies decode-safe normalization to every historical draft. Future migrations
    /// belong here and are activated by bumping HarvestModel.currentRecipeRepairRevision.
    func repairExisting() throws -> Int {
        try loadIfNeeded()
        var repaired = 0
        for index in recipes.indices {
            var recipe = recipes[index]
            let before = try? JSONCoding.encoder().encode(recipe)
            if let parsed = try? URLSafety.validatedRemoteURL(recipe.source.url) {
                recipe.source.url = URLSafety.normalized(parsed).absoluteString
            }
            if let canonical = recipe.source.canonicalURL,
               let parsed = try? URLSafety.validatedRemoteURL(canonical) {
                recipe.source.canonicalURL = URLSafety.normalized(parsed).absoluteString
            }
            recipe.source.host = URL(string: recipe.source.canonicalURL ?? recipe.source.url)?.host
                ?? recipe.source.host
            recipe.source.attribution = SourceAttribution.displayName(
                host: recipe.source.host,
                sourceName: recipe.source.attribution,
                author: recipe.source.author
            )
            recipe.categories = recipe.categories.cleanedUnique()
            recipe.cuisines = recipe.cuisines.cleanedUnique()
            recipe.diets = recipe.diets.cleanedUnique()
            recipe.keywords = recipe.keywords.cleanedUnique()
            recipe.warnings = recipe.warnings.cleanedUnique()
            recipe.categories = enrichedCategories(for: recipe)
            recipe.refreshFingerprint()
            let after = try? JSONCoding.encoder().encode(recipe)
            if before != after {
                recipe.updatedAt = Date()
                recipes[index] = recipe
                repaired += 1
            }
        }
        if repaired > 0 { try persist() }
        return repaired
    }

    /// Structured recipeCategory remains authoritative. Taxonomy matches supplement it
    /// from the recipe itself and its source path, including links mined from categories.
    private func enrichedCategories(for recipe: RecipeDraft) -> [String] {
        let evidence = recipe.categories + recipe.cuisines + recipe.diets + recipe.keywords + [
            recipe.title,
            recipe.summary ?? "",
            recipe.source.canonicalURL ?? recipe.source.url,
        ]
        return (recipe.categories + RecipeBrowseTaxonomy.inferredCategoryNames(from: evidence))
            .cleanedUnique()
    }

    @discardableResult
    func setReviewState(_ state: ReviewState, for ids: Set<UUID>) throws -> [RecipeDraft] {
        try loadIfNeeded()
        var changed: [RecipeDraft] = []
        for index in recipes.indices where ids.contains(recipes[index].id) {
            recipes[index].reviewState = state
            recipes[index].updatedAt = Date()
            changed.append(recipes[index])
        }
        try persist()
        return changed
    }

    /// Recipes that share this recipe's source URL or its normalised content.
    func duplicates(for recipe: RecipeDraft) throws -> [RecipeDraft] {
        try loadIfNeeded()
        return recipes.filter { candidate in
            guard candidate.id != recipe.id else { return false }
            if !recipe.sourceFingerprint.isEmpty,
               candidate.sourceFingerprint == recipe.sourceFingerprint {
                return true
            }
            guard let fingerprint = recipe.contentFingerprint, !fingerprint.isEmpty else {
                return false
            }
            return candidate.contentFingerprint == fingerprint
        }
    }

    /// Every group of two or more recipes with identical normalised content.
    func duplicateGroups() throws -> [[RecipeDraft]] {
        try loadIfNeeded()
        var buckets: [String: [RecipeDraft]] = [:]
        for recipe in recipes {
            guard let fingerprint = recipe.contentFingerprint, !fingerprint.isEmpty else { continue }
            buckets[fingerprint, default: []].append(recipe)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.createdAt < $1.createdAt } }
            .sorted { ($0.first?.title ?? "") < ($1.first?.title ?? "") }
    }

    // MARK: - Persistence

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loaded = true
            recipes = []
            return
        }
        do {
            recipes = try JSONCoding.decoder().decode(
                [RecipeDraft].self,
                from: Data(contentsOf: fileURL)
            )
            loaded = true
        } catch {
            // Preserve the unreadable file, then start clean instead of leaving
            // the library permanently unopenable.
            let backup = fileURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            loaded = true
            recipes = []
            throw CompanionError.persistence(
                "harvest-recipes.json could not be read (\(error.localizedDescription)). "
                    + "It was preserved as \(backup.lastPathComponent) and a new library was started."
            )
        }
    }

    private func persist() throws {
        do {
            // Compact, not pretty-printed. Nothing reads this file by eye, and the
            // indentation added 30–40% to a file that is rewritten on every change.
            let data = try JSONCoding.encoder().encode(recipes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw CompanionError.persistence(
                "recipes.json could not be written: \(error.localizedDescription)"
            )
        }
    }
}
