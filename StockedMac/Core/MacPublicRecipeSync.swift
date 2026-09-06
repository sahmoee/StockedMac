import Foundation
import Observation

/// Reads the same public recipe records used by iOS, without a household gate.
@MainActor @Observable
final class MacPublicRecipeSync {
    static let shared = MacPublicRecipeSync()
    private(set) var isSyncing = false
    private(set) var status: String
    private(set) var lastCompleteCount: Int?
    private(set) var lastCompletedAt: Date?
    private(set) var pagesLoaded = 0
    private(set) var rejectedCount = 0
    @ObservationIgnored private var loop: Task<Void, Never>?

    private static let cursorKey = "publicRecipeCatalogueCursor.v1"
    private static let completedAtKey = "publicRecipeCatalogueCompletedAt.v1"
    private static let completedCountKey = "publicRecipeCatalogueCompletedCount.v1"

    init(defaults: UserDefaults = .standard) {
        let timestamp = defaults.double(forKey: Self.completedAtKey)
        let count = defaults.object(forKey: Self.completedCountKey) as? Int
        lastCompletedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        lastCompleteCount = count
        status = count.map { "\($0) cached shared recipes · checking for updates" }
            ?? "Shared catalogue not yet refreshed"
    }

    func start(store: MacKitchenStore) {
        guard loop == nil else { return }
        loop = Task { [weak self, weak store] in
            // The durable on-disk catalogue is available immediately. Give AppKit and
            // the Harvester time to finish restoring the window before doing network
            // decoding/merging; otherwise independent launch jobs briefly compete for
            // the same core and make an already-cached library feel slow.
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            while !Task.isCancelled {
                guard let self, let store else { return }
                // Four 100-row pages is a large warm batch without decoding the complete
                // remote catalogue in one launch. The committed cursor resumes next pass.
                await self.refresh(store: store, maxPages: 4)
                do { try await Task.sleep(for: .seconds(900)) } catch { return }
            }
        }
    }

    func refresh(store: MacKitchenStore, maxPages: Int = 4) async {
        guard !isSyncing else { return }
        guard MacWorkerClient.isConfigured else {
            status = "Configure the Worker to load the shared catalogue"
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        var cursor = UserDefaults.standard.string(forKey: Self.cursorKey)
        var seenCursors = Set(cursor.map { [$0] } ?? [])
        var identities = Set<String>()
        var pendingRecipes: [UserRecipe] = []
        var pendingCursor: String?
        pagesLoaded = 0
        rejectedCount = 0
        do {
            repeat {
                try Task.checkCancellation()
                var query = ["pageSize": "100"]
                if let cursor { query["cursor"] = cursor }
                let data = try await MacWorkerClient.getData(path: "harvest/recipes", query: query, timeout: 45)
                let base = MacBuildConfig.receiptWorkerURL
                let page = try await Task.detached(priority: .utility) {
                    try MacPublicRecipePage.decode(data, baseURL: base)
                }.value
                try Task.checkCancellation()
                pagesLoaded += 1
                rejectedCount += page.rejectedCount
                // Merge text/URLs only. Artwork is fetched by visible rows, never by a
                // whole-library image download that delays browsing or spikes memory.
                pendingRecipes.append(contentsOf: page.recipes)
                for recipe in page.recipes { identities.insert(MacPublicRecipePage.identity(recipe)) }
                status = "Loading page \(pagesLoaded) · \(identities.count) shared recipes"
                guard let complete = page.complete else {
                    store.mergePublicRecipes(pendingRecipes)
                    status = "Loaded legacy catalogue; server update needed for all recipes"
                    return
                }
                if complete {
                    store.mergePublicRecipes(pendingRecipes)
                    UserDefaults.standard.removeObject(forKey: Self.cursorKey)
                    lastCompleteCount = store.recipes.count
                    let completedAt = Date()
                    lastCompletedAt = completedAt
                    UserDefaults.standard.set(store.recipes.count, forKey: Self.completedCountKey)
                    UserDefaults.standard.set(completedAt.timeIntervalSince1970, forKey: Self.completedAtKey)
                    status = "\(store.recipes.count) cached recipes · catalogue up to date"
                        + (rejectedCount == 0 ? "" : " · \(rejectedCount) invalid records skipped")
                    return
                }
                guard let next = page.nextCursor, !next.isEmpty, seenCursors.insert(next).inserted else {
                    throw MacServiceError.malformedResponse("Catalogue pagination did not advance")
                }
                cursor = next
                pendingCursor = next
                if pagesLoaded >= max(1, maxPages) {
                    // Coalesce the warm batch into one observable mutation and one
                    // complete-library JSON write. Four page-by-page writes previously
                    // produced a sustained full-core burst on an 11k-recipe library.
                    store.mergePublicRecipes(pendingRecipes)
                    UserDefaults.standard.set(next, forKey: Self.cursorKey)
                    status = "\(store.recipes.count) recipes cached · more updates scheduled"
                    return
                }
                // Pages are deliberately paced. Nothing visible waits for this because
                // prior pages remain in the durable local cache.
                do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            } while !Task.isCancelled
        } catch {
            // Retain completely decoded pages even if a later request fails. The cursor
            // advances only after their single coalesced write has been scheduled.
            if !pendingRecipes.isEmpty {
                store.mergePublicRecipes(pendingRecipes)
                if let pendingCursor { UserDefaults.standard.set(pendingCursor, forKey: Self.cursorKey) }
            }
            status = "Catalogue refresh incomplete · \(error.localizedDescription)"
        }
    }
}

nonisolated struct MacPublicRecipePage: Sendable {
    var recipes: [UserRecipe]
    var complete: Bool?
    var nextCursor: String?
    var rejectedCount: Int = 0

    static func identity(_ recipe: UserRecipe) -> String {
        guard let raw = recipe.sourceURL, var url = URLComponents(string: raw) else { return recipe.id.uuidString }
        url.fragment = nil
        url.queryItems = url.queryItems?.filter {
            !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid", "ref"].contains($0.name.lowercased())
        }
        if url.queryItems?.isEmpty == true { url.queryItems = nil }
        url.scheme = url.scheme?.lowercased()
        url.host = url.host?.lowercased()
        if url.port == 443 { url.port = nil }
        if url.path.count > 1 && url.path.hasSuffix("/") { url.path.removeLast() }
        return url.string ?? raw
    }

    static func decode(_ data: Data, baseURL: String) throws -> Self {
        guard data.count <= 16 * 1024 * 1024 else {
            throw MacServiceError.malformedResponse("Catalogue page is too large")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["recipes"] as? [[String: Any]] else {
            throw MacServiceError.malformedResponse("Missing catalogue recipes")
        }
        // Legacy unpaged responses remain compatible with the retained server index.
        guard rows.count <= (object["complete"] == nil ? 8000 : 100) else {
            throw MacServiceError.malformedResponse("Catalogue page exceeds the record limit")
        }
        let formatter = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: text) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        let recipes = rows.compactMap { row -> UserRecipe? in
            guard let rawID = row["id"] as? String, !rawID.isEmpty,
                  let rawTitle = row["title"] as? String,
                  let source = row["sourceURL"] as? String,
                  let sourceURL = URL(string: source), sourceURL.scheme?.lowercased() == "https", sourceURL.host != nil,
                  sourceURL.user == nil, sourceURL.password == nil,
                  let rawSteps = row["instructions"] as? [String] else { return nil }
            let title = RecipeTitlePolicy.cleaned(rawTitle)
            let steps = rawSteps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !title.isEmpty, title.count <= 500, !steps.isEmpty else { return nil }
            let rawImage = (row["imageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? row["image"] as? String ?? ""
            guard !rawImage.isEmpty,
                  let image = URL(string: rawImage, relativeTo: URL(string: baseURL))?.absoluteURL,
                  image.scheme?.lowercased() == "https", image.host != nil,
                  image.user == nil, image.password == nil,
                  MacRecipeImagePolicy.isLikelyRecipeImageURL(image.absoluteString, sourceURL: source) else { return nil }
            var recipe = UserRecipe(title: title)
            if let uuid = UUID(uuidString: rawID) { recipe.id = uuid }
            else {
                // Match iOS HarvestWireRecipe's stable UUID for historical non-UUID ids.
                func hash(_ input: String) -> UInt64 {
                    input.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
                }
                let bytes = [hash(rawID), hash("harvest-salt::" + rawID)].flatMap { value in
                    (0..<8).map { UInt8((value >> (8 * UInt64(7 - $0))) & 0xff) }
                }
                recipe.id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            }
            recipe.description = row["description"] as? String ?? ""
            recipe.instructions = steps
            recipe.ingredients = (row["ingredients"] as? [[String: Any]] ?? []).compactMap {
                guard let raw = $0["name"] as? String else { return nil }
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return RecipeIngredient(name: name, amount: ($0["amount"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard !recipe.ingredients.isEmpty else { return nil }
            recipe.imageURL = image.absoluteString
            recipe.sourceURL = source
            recipe.sourceName = row["attribution"] as? String ?? sourceURL.host
            recipe.author = row["author"] as? String
            recipe.license = row["license"] as? String
            recipe.imageAttribution = row["imageAttribution"] as? String
            recipe.notes = [("Author", recipe.author), ("Recipe license", recipe.license), ("Photo credit", recipe.imageAttribution)]
                .compactMap { key, value in value?.nilIfBlank.map { "\(key): \($0)" } }.joined(separator: "\n")
            var seenTags = Set<String>()
            recipe.tags = (row["tags"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seenTags.insert($0.lowercased()).inserted }
            recipe.categories = row["categories"] as? [String]
            recipe.cuisine = row["cuisine"] as? String ?? ""
            recipe.servings = min(1000, max(1, row["servings"] as? Int ?? 4))
            recipe.prepTime = row["prepTime"] as? String ?? ""
            recipe.cookTime = row["cookTime"] as? String ?? ""
            recipe.dateCreated = date(row["importedAt"]) ?? date(row["storedAt"]) ?? .distantPast
            recipe.updatedAt = row["updatedAt"] as? Double ?? (date(row["storedAt"]) ?? recipe.dateCreated).timeIntervalSince1970 * 1000
            recipe.lastWriterID = "shared-catalogue"
            return recipe
        }
        return Self(recipes: recipes, complete: object["complete"] as? Bool, nextCursor: object["nextCursor"] as? String,
                    rejectedCount: rows.count - recipes.count)
    }
}
