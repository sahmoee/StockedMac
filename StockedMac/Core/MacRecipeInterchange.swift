import Foundation

/// Independent, local implementation of https://schema.org/Recipe. No hosted parser,
/// recipe catalogue, or third-party source code is embedded in this importer.
nonisolated struct MacInterchangeRecipe: Identifiable, Sendable {
    var id = UUID()
    var title = ""
    var summary = ""
    var privateNotes = ""
    var sourceURL = ""
    var sourceName = ""
    var author = ""
    var license = ""
    var imageCredit = ""
    var imageURL = ""
    var ingredients: [String] = []
    var instructions: [String] = []
    var yield = ""
    var prepTime = ""
    var cookTime = ""
    var totalTime = ""
    var cuisines: [String] = []
    var categories: [String] = []
    var tags: [String] = []
    var nutrition: [String: String] = [:]
    var warnings: [String] = []
    var originalCooklang: String?
    var originalFilename: String?
    var rawOriginalText: String?
    var originalFormat: String?
    var originalHash: String?
    var localImageData: Data?

    var contentProblems: [String] {
        var result: [String] = []
        if title.isEmpty { result.append("Missing recipe title.") }
        if ingredients.isEmpty { result.append("Missing ingredients.") }
        if instructions.isEmpty { result.append("Missing cooking steps.") }
        if localImageData == nil && MacRecipeInterchange.secureURL(imageURL) == nil { result.append("Missing a usable local photo or secure recipe photo URL.") }
        return result
    }

    var publicationProblems: [String] {
        MacRecipeInterchange.secureURL(sourceURL) == nil ? ["Public sharing requires a secure original source URL. Keep this recipe in your household instead."] : []
    }

    /// No title-only merging: two publishers can have different recipes with the same title.
    var sourceKey: String? { MacRecipeInterchange.sourceKey(sourceURL) }
}

nonisolated enum MacRecipeInterchange {
    static let byteLimit = 8 * 1_024 * 1_024
    static let recipeLimit = 250

    enum ImportError: LocalizedError {
        case tooLarge, tooMany, noRecipes, malformed
        var errorDescription: String? {
            switch self {
            case .tooLarge: "Use a file smaller than 8 MB."
            case .tooMany: "Split this file into batches of at most 250 recipes."
            case .noRecipes: "No Schema.org Recipe records were found. Choose a Recipe JSON or JSON-LD export. App-specific backups use their own format."
            case .malformed: "The file is not readable JSON or JSON-LD."
            }
        }
    }

    static func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        guard data.count <= byteLimit else { throw ImportError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> [MacInterchangeRecipe] {
        guard data.count <= byteLimit else { throw ImportError.tooLarge }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ImportError.malformed }
        var records: [[String: Any]] = []
        func visit(_ value: Any, depth: Int) throws {
            guard depth <= 24 else { throw ImportError.malformed }
            if let array = value as? [Any] {
                for item in array { try visit(item, depth: depth + 1) }
            } else if let object = value as? [String: Any] {
                let types = strings(object["@type"])
                if types.contains(where: { $0 == "Recipe" || $0 == "https://schema.org/Recipe" || $0 == "http://schema.org/Recipe" }) {
                    records.append(object)
                    guard records.count <= recipeLimit else { throw ImportError.tooMany }
                    return
                }
                // Known JSON-LD/container shapes only; never interpret arbitrary objects
                // or user notes as more recipes.
                for key in ["@graph", "mainEntity", "itemListElement", "item", "recipes"] {
                    if let nested = object[key] { try visit(nested, depth: depth + 1) }
                }
            }
        }
        try visit(root, depth: 0)
        guard !records.isEmpty else { throw ImportError.noRecipes }
        return records.map(decodeRecipe)
    }

    private static func decodeRecipe(_ object: [String: Any]) -> MacInterchangeRecipe {
        var recipe = MacInterchangeRecipe()
        recipe.title = text(object["name"])
        recipe.summary = text(object["description"])
        recipe.privateNotes = text(object["comment"])
        recipe.sourceURL = urlText(object["url"])
        if recipe.sourceURL.isEmpty { recipe.sourceURL = urlText(object["mainEntityOfPage"]) }
        if recipe.sourceURL.isEmpty { recipe.sourceURL = urlText(object["@id"]) }
        recipe.sourceName = text(object["publisher"])
        recipe.author = strings(object["author"]).joined(separator: ", ")
        recipe.license = urlText(object["license"])
        recipe.imageURL = urlText(object["image"])
        recipe.imageCredit = text(object["imageAttribution"])
        if let image = (object["image"] as? [String: Any]) ?? (object["image"] as? [[String: Any]])?.first {
            recipe.imageCredit = [recipe.imageCredit, text(image["creditText"]), text(image["copyrightNotice"]), urlText(image["license"])].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        recipe.ingredients = lines(object["recipeIngredient"])
        recipe.instructions = lines(object["recipeInstructions"])
        recipe.yield = text(object["recipeYield"])
        recipe.prepTime = text(object["prepTime"])
        recipe.cookTime = text(object["cookTime"])
        recipe.totalTime = text(object["totalTime"])
        recipe.cuisines = strings(object["recipeCuisine"])
        recipe.categories = strings(object["recipeCategory"])
        recipe.tags = strings(object["keywords"]).flatMap { $0.components(separatedBy: ",") }.map(clean).filter { !$0.isEmpty }
        if let nutrition = object["nutrition"] as? [String: Any] {
            for (key, value) in nutrition where !key.hasPrefix("@") {
                let entry = text(value)
                if !entry.isEmpty { recipe.nutrition[key] = entry }
            }
        }
        if recipe.license.isEmpty { recipe.warnings.append("The file does not state a recipe license. Check the source before publishing.") }
        if !recipe.yield.isEmpty, Double(recipe.yield) == nil {
            recipe.warnings.append("Yield is kept as written; verify the serving count after import.")
        }
        if !recipe.nutrition.isEmpty { recipe.warnings.append("Nutrition is preserved as source text, without guessing quantities or daily values.") }
        return recipe
    }

    static func encode(_ recipes: [MacInterchangeRecipe]) throws -> Data {
        let records = recipes.map { recipe -> [String: Any] in
            var value: [String: Any] = ["@type": "Recipe", "name": recipe.title,
                "recipeIngredient": recipe.ingredients,
                "recipeInstructions": recipe.instructions.map { ["@type": "HowToStep", "text": $0] }]
            for (key, entry) in [("description", recipe.summary), ("url", recipe.sourceURL), ("author", recipe.author),
                                 ("publisher", recipe.sourceName), ("license", recipe.license), ("recipeYield", recipe.yield),
                                 ("prepTime", recipe.prepTime), ("cookTime", recipe.cookTime), ("totalTime", recipe.totalTime)] where !entry.isEmpty {
                value[key] = entry
            }
            if !recipe.imageURL.isEmpty {
                var image = ["@type": "ImageObject", "url": recipe.imageURL]
                if !recipe.imageCredit.isEmpty { image["creditText"] = recipe.imageCredit }
                value["image"] = image
            }
            if !recipe.cuisines.isEmpty { value["recipeCuisine"] = recipe.cuisines }
            if !recipe.categories.isEmpty { value["recipeCategory"] = recipe.categories }
            if !recipe.tags.isEmpty { value["keywords"] = recipe.tags }
            if !recipe.privateNotes.isEmpty { value["comment"] = ["@type": "Comment", "text": recipe.privateNotes] }
            if !recipe.nutrition.isEmpty { value["nutrition"] = recipe.nutrition.merging(["@type": "NutritionInformation"]) { first, _ in first } }
            return value
        }
        return try JSONSerialization.data(withJSONObject: ["@context": "https://schema.org", "@graph": records], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func secureURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              !host.lowercased().hasSuffix(".local"), host.lowercased() != "localhost",
              !host.contains(":"), host.first?.isNumber != true else { return nil }
        return url
    }

    static func sourceKey(_ value: String) -> String? {
        guard let url = secureURL(value), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        // Path and query casing can identify different recipes. Do not lowercase them.
        return parts.string
    }

    private static func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func text(_ value: Any?) -> String {
        if let string = value as? String { return clean(string) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        if let array = value as? [Any] { return array.map { text($0) }.filter { !$0.isEmpty }.joined(separator: ", ") }
        if let object = value as? [String: Any] { return text(object["name"] ?? object["text"] ?? object["value"]) }
        return ""
    }

    private static func strings(_ value: Any?) -> [String] {
        if let array = value as? [Any] { return array.map { text($0) }.filter { !$0.isEmpty } }
        let result = text(value)
        return result.isEmpty ? [] : [result]
    }

    private static func urlText(_ value: Any?) -> String {
        if let array = value as? [Any] { return array.map { urlText($0) }.first { !$0.isEmpty } ?? "" }
        if let object = value as? [String: Any] { return urlText(object["url"] ?? object["contentUrl"] ?? object["@id"]) }
        return text(value)
    }

    private static func lines(_ value: Any?, depth: Int = 0) -> [String] {
        guard depth <= 24 else { return [] }
        if let array = value as? [Any] { return array.flatMap { lines($0, depth: depth + 1) } }
        if let object = value as? [String: Any] {
            if let children = object["itemListElement"] ?? object["steps"] {
                let heading = text(object["name"])
                let children = lines(children, depth: depth + 1)
                return heading.isEmpty ? children : [heading + ":"] + children
            }
            if let item = object["item"] { return lines(item, depth: depth + 1) }
            let line = text(object["text"] ?? object["name"] ?? object["value"])
            return line.isEmpty ? [] : [line]
        }
        return text(value).components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
    }
}
