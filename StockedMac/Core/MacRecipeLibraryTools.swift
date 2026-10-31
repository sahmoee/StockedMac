// MacRecipeLibraryTools.swift — pure, Mac-only recipe-management helpers.
//
// Build 114 desktop batch. Everything here is deterministic and free of UI so it can run
// off the main actor on large libraries. Nothing in this file changes the shared recipe
// schema: bulk edits, tag renames and duplicate variations all go through the existing
// MacKitchenStore mutation paths (stamping, image gate, portable-source repair, household
// tombstones). Display helpers (scaling, unit conversion, Markdown) never mutate records.

import Foundation

// MARK: - Library scope

/// A coarse library slice layered on top of the existing search/facet filters.
nonisolated enum MacRecipeScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "All recipes"
    case myCollection = "My collection"
    case personal = "Personal recipes"
    case imported = "Imported from sources"
    case withNotes = "Has notes"
    case needsAttention = "Needs attention"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "books.vertical"
        case .myCollection: return "heart.text.square"
        case .personal: return "person.crop.square"
        case .imported: return "globe"
        case .withNotes: return "note.text"
        case .needsAttention: return "exclamationmark.triangle"
        }
    }

    func includes(_ recipe: UserRecipe) -> Bool {
        switch self {
        case .all: return true
        case .myCollection: return recipe.belongsToMyCollection
        case .personal: return recipe.attributedSourceURL?.nilIfBlank == nil
        case .imported: return recipe.attributedSourceURL?.nilIfBlank != nil
        case .withNotes: return recipe.notes.nilIfBlank != nil
        case .needsAttention: return !MacRecipeHealth.issues(for: recipe).isEmpty
        }
    }
}

// MARK: - Saved filters

/// A named snapshot of the Recipes index filters. Presentation state only — stored in
/// this Mac's preferences and never synced or written into recipe records.
nonisolated struct MacSavedRecipeFilter: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var search: String = ""
    var sort: String = "Name"
    var favoritesOnly = false
    var cuisine: String = ""
    var tag: String = ""
    var difficulty: String = ""
    var role: String = ""
    var scope: MacRecipeScope = .all
    var createdAt = Date()

    var summary: String {
        var parts: [String] = []
        if let search = search.nilIfBlank { parts.append("“\(search)”") }
        if scope != .all { parts.append(scope.rawValue) }
        if favoritesOnly { parts.append("Favorites") }
        if let cuisine = cuisine.nilIfBlank { parts.append(cuisine) }
        if let tag = tag.nilIfBlank { parts.append("#\(tag)") }
        if let difficulty = difficulty.nilIfBlank { parts.append(difficulty) }
        if !role.isEmpty { parts.append(DishRole(rawValue: role)?.label ?? role) }
        parts.append("sorted by \(sort.lowercased())")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Time

nonisolated enum MacRecipeTiming {
    /// Prep + cook minutes when either is readable, otherwise nil (sorted last).
    static func totalMinutes(_ recipe: UserRecipe) -> Int? {
        let prep = HarvestWorkerParser.minutes(from: recipe.prepTime)
        let cook = HarvestWorkerParser.minutes(from: recipe.cookTime)
        guard prep != nil || cook != nil else { return nil }
        return (prep ?? 0) + (cook ?? 0)
    }
}

// MARK: - Health audit

nonisolated enum MacRecipeHealthIssue: String, CaseIterable, Identifiable, Sendable {
    case missingImage = "Image not validated"
    case missingCuisine = "No cuisine"
    case missingDescription = "No description"
    case missingTime = "No prep or cook time"
    case thinMethod = "Fewer than two steps"
    case fewIngredients = "Fewer than two ingredients"
    case shoutingTitle = "Title needs casing"
    case missingAttribution = "Source without publisher name"
    case unusualServings = "Unusual serving count"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .missingImage: return "photo.badge.exclamationmark"
        case .missingCuisine: return "globe.europe.africa"
        case .missingDescription: return "text.alignleft"
        case .missingTime: return "clock.badge.questionmark"
        case .thinMethod: return "list.number"
        case .fewIngredients: return "list.bullet"
        case .shoutingTitle: return "textformat"
        case .missingAttribution: return "link.badge.plus"
        case .unusualServings: return "person.2.badge.gearshape"
        }
    }

    var advice: String {
        switch self {
        case .missingImage: return "Add or repair the HTTPS image so the recipe can sync and publish."
        case .missingCuisine: return "Set a cuisine so collections and iOS browse filters can find it."
        case .missingDescription: return "A one-line description improves search and catalogue cards."
        case .missingTime: return "Add a prep or cook time so time sorting and iOS filters work."
        case .thinMethod: return "Check the method for merged or missing steps."
        case .fewIngredients: return "Check whether ingredients were merged into one line."
        case .shoutingTitle: return "Titles written entirely in capitals read poorly on cards."
        case .missingAttribution: return "Name the original publisher for honest attribution."
        case .unusualServings: return "Servings outside 1–50 usually mean a parsing mistake."
        }
    }
}

nonisolated enum MacRecipeHealth {
    static func issues(for recipe: UserRecipe) -> [MacRecipeHealthIssue] {
        var result: [MacRecipeHealthIssue] = []
        if !MacRecipeImagePolicy.hasRequiredImage(recipe) { result.append(.missingImage) }
        if recipe.cuisine.nilIfBlank == nil { result.append(.missingCuisine) }
        if recipe.description.nilIfBlank == nil { result.append(.missingDescription) }
        if recipe.prepTime.nilIfBlank == nil && recipe.cookTime.nilIfBlank == nil { result.append(.missingTime) }
        if recipe.instructions.filter({ $0.nilIfBlank != nil }).count < 2 { result.append(.thinMethod) }
        if recipe.ingredients.count < 2 { result.append(.fewIngredients) }
        let letters = recipe.title.filter(\.isLetter)
        if letters.count >= 6, letters == letters.uppercased() { result.append(.shoutingTitle) }
        if recipe.attributedSourceURL?.nilIfBlank != nil, recipe.sourceName?.nilIfBlank == nil {
            result.append(.missingAttribution)
        }
        if recipe.servings < 1 || recipe.servings > 50 { result.append(.unusualServings) }
        return result
    }

    struct Report: Sendable {
        var byIssue: [MacRecipeHealthIssue: [UUID]] = [:]
        var affectedCount = 0
        var total = 0
        var healthyPercent: Int {
            total == 0 ? 100 : Int((Double(total - affectedCount) / Double(total) * 100).rounded())
        }
    }

    static func report(_ recipes: [UserRecipe]) -> Report {
        var report = Report(total: recipes.count)
        for recipe in recipes {
            let found = issues(for: recipe)
            if !found.isEmpty { report.affectedCount += 1 }
            for issue in found { report.byIssue[issue, default: []].append(recipe.id) }
        }
        return report
    }
}

// MARK: - Duplicate detection

nonisolated struct MacDuplicateGroup: Identifiable, Sendable {
    var id: String { ids.map(\.uuidString).sorted().joined(separator: "|") }
    /// First element is the recommended keeper.
    var ids: [UUID]
    var reason: String
}

nonisolated enum MacRecipeDuplicates {
    /// Groups recipes that share a canonical source URL, or an identical normalized title
    /// with the same leading ingredient set. Title-only matches are never grouped: two
    /// publishers can legitimately share a title.
    static func groups(_ recipes: [UserRecipe]) -> [MacDuplicateGroup] {
        var parent = Array(recipes.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[rb] = ra } }

        var bySource: [String: Int] = [:]
        var byContent: [String: Int] = [:]
        var reasons: [Int: String] = [:]
        for index in recipes.indices {
            let recipe = recipes[index]
            if let source = recipe.attributedSourceURL?.nilIfBlank {
                var copy = recipe
                copy.sourceURL = source
                let key = MacPublicRecipePage.identity(copy).lowercased()
                if let existing = bySource[key] { union(existing, index); reasons[index] = "Same original source" }
                else { bySource[key] = index }
            }
            let title = normalizedTitle(RecipeTitlePolicy.cleaned(recipe.title))
            guard !title.isEmpty, !recipe.ingredients.isEmpty else { continue }
            let ingredients = recipe.ingredients.prefix(6).map { normalizedTitle($0.name) }.sorted().joined(separator: ",")
            let key = title + "#" + ingredients
            if let existing = byContent[key] {
                union(existing, index)
                if reasons[index] == nil { reasons[index] = "Same title and ingredients" }
            } else { byContent[key] = index }
        }

        var clusters: [Int: [Int]] = [:]
        for index in recipes.indices { clusters[find(index), default: []].append(index) }
        return clusters.values.filter { $0.count > 1 }.map { members in
            let ranked = members.sorted { keepScore(recipes[$0]) > keepScore(recipes[$1]) }
            let reason = members.compactMap { reasons[$0] }.first ?? "Matching recipe"
            return MacDuplicateGroup(ids: ranked.map { recipes[$0].id }, reason: reason)
        }.sorted { $0.ids.count == $1.ids.count ? $0.id < $1.id : $0.ids.count > $1.ids.count }
    }

    /// Personal annotations win, then the richer record, then the newer edit.
    static func keepScore(_ recipe: UserRecipe) -> Double {
        var score = 0.0
        if recipe.isFavorited { score += 1_000 }
        if recipe.notes.nilIfBlank != nil { score += 500 }
        if recipe.cookCount > 0 { score += 400 }
        if recipe.collectionSavedByUser == true { score += 300 }
        if MacRecipeImagePolicy.hasRequiredImage(recipe) { score += 200 }
        score += Double(min(recipe.ingredients.count, 40) + min(recipe.instructions.count, 40))
        score += recipe.updatedAt / 1e13
        return score
    }
}

// MARK: - Bulk edit

nonisolated struct MacRecipeBulkEdit: Sendable, Equatable {
    var addTags: [String] = []
    var removeTags: [String] = []
    var cuisine: String? = nil
    var clearCuisine = false
    var difficulty: String? = nil
    var role: DishRole? = nil
    var favorite: Bool? = nil

    var isEmpty: Bool {
        addTags.isEmpty && removeTags.isEmpty && cuisine == nil && !clearCuisine
            && difficulty == nil && role == nil && favorite == nil
    }

    func apply(to recipe: inout UserRecipe) {
        let removal = Set(removeTags.map(MacRecipeTags.key))
        recipe.tags.removeAll { removal.contains(MacRecipeTags.key($0)) }
        recipe.tags = MacRecipeTags.unique(recipe.tags + addTags)
        if clearCuisine { recipe.cuisine = "" }
        if let cuisine = cuisine?.nilIfBlank { recipe.cuisine = cuisine }
        if let difficulty { recipe.difficulty = difficulty }
        if let role { recipe.dishRole = role }
        if let favorite { recipe.isFavorited = favorite }
    }
}

nonisolated enum MacRecipeTags {
    static func key(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func unique(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(key(value)).inserted else { return nil }
            return value
        }
    }

    static func parse(_ text: String) -> [String] {
        unique(text.components(separatedBy: CharacterSet(charactersIn: ",\n")))
    }

    struct Usage: Identifiable, Sendable {
        var id: String { key }
        var key: String
        var display: String
        var count: Int
        var variants: [String]
    }

    static func usage(_ recipes: [UserRecipe]) -> [Usage] {
        var counts: [String: (display: String, count: Int, variants: Set<String>)] = [:]
        for recipe in recipes {
            for tag in Set(recipe.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !tag.isEmpty {
                let k = key(tag)
                var entry = counts[k] ?? (tag, 0, [])
                entry.count += 1
                entry.variants.insert(tag)
                counts[k] = entry
            }
        }
        return counts.map { Usage(key: $0.key, display: $0.value.display, count: $0.value.count,
                                  variants: $0.value.variants.sorted()) }
            .sorted { $0.count == $1.count
                ? $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
                : $0.count > $1.count }
    }

    /// Replaces every spelling of `old` with `new`, merging into an existing tag when the
    /// new name already exists. Returns nil when the recipe does not carry the tag.
    static func renamed(_ tags: [String], from old: String, to new: String) -> [String]? {
        let oldKey = key(old)
        guard tags.contains(where: { key($0) == oldKey }) else { return nil }
        let replaced = tags.map { key($0) == oldKey ? new.trimmingCharacters(in: .whitespacesAndNewlines) : $0 }
        return unique(replaced)
    }

    static func removing(_ tags: [String], _ old: String) -> [String]? {
        let oldKey = key(old)
        guard tags.contains(where: { key($0) == oldKey }) else { return nil }
        return tags.filter { key($0) != oldKey }
    }
}

// MARK: - Variations

nonisolated enum MacRecipeVariation {
    /// A personal, household-only copy. The original publisher stays credited in the
    /// description footer and notes, but the copy carries no public source URL, so it can
    /// never be republished into the shared catalogue as a second import.
    static func make(from original: UserRecipe) -> UserRecipe {
        var copy = original
        copy.id = UUID()
        copy.title = "\(original.title) (variation)"
        copy.sourceURL = nil
        copy.portableSource = nil
        copy.collectionSavedByUser = true
        copy.isFavorited = false
        copy.cookCount = 0
        copy.lastCooked = nil
        copy.dateCreated = Date()
        copy.updatedAt = 0
        copy.lastWriterID = ""
        var credit: [String] = []
        let publisher = original.sourceName?.nilIfBlank
        if let url = original.attributedSourceURL?.nilIfBlank {
            credit.append("Adapted from \(publisher ?? "the original recipe") — \(url)")
        } else if let publisher {
            credit.append("Adapted from \(publisher)")
        } else {
            credit.append("Adapted from “\(original.title)”")
        }
        copy.sourceName = nil
        copy.notes = ([credit.joined()] + [original.notes.nilIfBlank].compactMap { $0 }).joined(separator: "\n\n")
        return copy
    }
}

// MARK: - Text exports

nonisolated enum MacRecipeTextExport {
    static func ingredientLine(_ ingredient: RecipeIngredient, factor: Double = 1,
                               system: MacMeasurementSystem = .asWritten) -> String {
        let amount = MacMeasurementConverter.display(ingredient.amount, factor: factor, system: system)
        var line = amount.isEmpty ? ingredient.name : "\(amount) \(ingredient.name)"
        if let prep = ingredient.prep?.nilIfBlank { line += ", \(prep)" }
        if ingredient.isOptional { line += " (optional)" }
        return line
    }

    static func markdown(_ recipe: UserRecipe, factor: Double = 1,
                         system: MacMeasurementSystem = .asWritten, includeNotes: Bool = true) -> String {
        var lines = ["# \(recipe.title)", ""]
        if let image = recipe.imageURL?.nilIfBlank, image.hasPrefix("https://") {
            lines += ["![\(recipe.title)](\(image))", ""]
        }
        if let description = recipe.description.nilIfBlank { lines += ["_\(description)_", ""] }
        var facts: [String] = []
        let servings = max(1, Int((Double(recipe.servings) * factor).rounded()))
        facts.append("**Serves** \(servings)")
        if let prep = recipe.prepTime.nilIfBlank { facts.append("**Prep** \(prep)") }
        if let cook = recipe.cookTime.nilIfBlank { facts.append("**Cook** \(cook)") }
        if let cuisine = recipe.cuisine.nilIfBlank { facts.append("**Cuisine** \(cuisine)") }
        if recipe.dishRole != .unspecified { facts.append("**Role** \(recipe.dishRole.label)") }
        lines += [facts.joined(separator: " · "), ""]
        if !recipe.tags.isEmpty { lines += ["Tags: " + recipe.tags.map { "`\($0)`" }.joined(separator: " "), ""] }
        lines += ["## Ingredients", ""]
        lines += recipe.ingredients.map { "- " + ingredientLine($0, factor: factor, system: system) }
        lines += ["", "## Method", ""]
        lines += recipe.instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if includeNotes, let notes = recipe.notes.nilIfBlank {
            lines += ["", "## Notes", "", notes]
        }
        var credits: [String] = []
        if let url = recipe.attributedSourceURL?.nilIfBlank {
            credits.append("Source: [\(recipe.sourceName?.nilIfBlank ?? URL(string: url)?.host ?? "Original recipe")](\(url))")
        } else if let name = recipe.sourceName?.nilIfBlank {
            credits.append("Source: \(name)")
        }
        if let author = recipe.author?.nilIfBlank { credits.append("Author: \(author)") }
        if let license = recipe.license?.nilIfBlank { credits.append("Recipe license: \(license)") }
        if let photo = recipe.imageAttribution?.nilIfBlank { credits.append("Photo credit: \(photo)") }
        if !credits.isEmpty { lines += ["", "---", ""] + credits.map { $0 + "  " } }
        return lines.joined(separator: "\n") + "\n"
    }

    static func plainText(_ recipe: UserRecipe, factor: Double = 1, system: MacMeasurementSystem = .asWritten) -> String {
        var lines = [recipe.title]
        if let description = recipe.description.nilIfBlank { lines += ["", description] }
        lines += ["", "INGREDIENTS"] + recipe.ingredients.map { "• " + ingredientLine($0, factor: factor, system: system) }
        lines += ["", "METHOD"] + recipe.instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if let url = recipe.attributedSourceURL?.nilIfBlank { lines += ["", "Source: \(recipe.sourceName ?? url) — \(url)"] }
        return lines.joined(separator: "\n")
    }

    static func cooklang(_ recipe: UserRecipe) -> String {
        PortableCooklang.export(MacRecipeInterchangeAdapter.cooklang(MacRecipeInterchangeAdapter.document(recipe)))
    }

    static func safeFilename(_ title: String, id: UUID) -> String {
        let base = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let trimmed = String((base.isEmpty ? "Recipe" : base).prefix(80))
        return "\(trimmed)-\(id.uuidString.prefix(8))"
    }

    /// Writes one Markdown file per recipe into a new subfolder. Off-main friendly.
    static func writeMarkdownFolder(_ recipes: [UserRecipe], into directory: URL, includeNotes: Bool) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = directory.appendingPathComponent("Stocked Recipes \(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var index = ["# Stocked recipes", "", "Exported \(recipes.count) recipes.", ""]
        for recipe in recipes {
            try Task.checkCancellation()
            let name = safeFilename(recipe.title, id: recipe.id) + ".md"
            try Data(markdown(recipe, includeNotes: includeNotes).utf8)
                .write(to: folder.appendingPathComponent(name), options: .atomic)
            index.append("- [\(recipe.title)](\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name))")
        }
        try Data((index.joined(separator: "\n") + "\n").utf8)
            .write(to: folder.appendingPathComponent("README.md"), options: .atomic)
        return folder
    }
}
