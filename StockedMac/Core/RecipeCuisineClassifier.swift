import Foundation

/// Conservative, deterministic cuisine inference shared by historical repair and every
/// future recipe ingress. It only returns Stocked's canonical cuisine names and never
/// replaces a value a parser or person already supplied.
nonisolated enum RecipeCuisineClassifier {
    nonisolated struct Evidence: Sendable {
        var title: String
        var summary: String
        var metadata: [String]
        var source: [String]
        var ingredients: [String]
    }

    private nonisolated struct Rule: Sendable {
        let cuisine: String
        let terms: [String]
    }

    /// Specific cuisines precede their regional parents so equal evidence resolves to
    /// the most useful label (notably Jamaican before Caribbean).
    private static let rules: [Rule] = [
        .init(cuisine: "Jamaican", terms: ["jamaican", "jamaica", "jerk chicken", "jerk pork", "ackee and saltfish"]),
        .init(cuisine: "Cajun & Creole", terms: ["cajun", "creole", "jambalaya", "etouffee", "gumbo"]),
        .init(cuisine: "Tex-Mex", terms: ["tex mex", "texmex", "fajitas", "chili con queso"]),
        .init(cuisine: "Soul Food", terms: ["soul food", "hoppin john"]),
        .init(cuisine: "Southern", terms: ["southern", "lowcountry", "country gravy"]),
        .init(cuisine: "New England", terms: ["new england", "maine lobster", "clam chowder"]),
        .init(cuisine: "Hawaiian", terms: ["hawaiian", "hawaii", "poke bowl", "loco moco", "kalua pork"]),
        .init(cuisine: "Mexican", terms: ["mexican", "mexico", "enchilada", "chilaquiles", "pozole", "tamales", "mole poblano"]),
        .init(cuisine: "Italian", terms: ["italian", "italy", "risotto", "carbonara", "bolognese", "parmigiana", "tiramisu"]),
        .init(cuisine: "French", terms: ["french", "france", "coq au vin", "ratatouille", "bouillabaisse", "croque monsieur"]),
        .init(cuisine: "Spanish", terms: ["spanish", "spain", "paella", "patatas bravas", "gazpacho"]),
        .init(cuisine: "Greek", terms: ["greek", "greece", "moussaka", "spanakopita", "souvlaki"]),
        .init(cuisine: "Moroccan", terms: ["moroccan", "morocco", "tagine", "harira"]),
        .init(cuisine: "Turkish", terms: ["turkish", "turkey cuisine", "menemen", "lahmacun"]),
        .init(cuisine: "Mediterranean", terms: ["mediterranean"]),
        .init(cuisine: "Middle Eastern", terms: ["middle eastern", "levantine", "lebanese", "persian", "iranian", "shawarma", "fattoush"]),
        .init(cuisine: "Indian", terms: ["indian", "india", "tikka masala", "vindaloo", "biryani", "dal makhani", "paneer"]),
        .init(cuisine: "Thai", terms: ["thai", "thailand", "pad thai", "tom yum", "tom kha"]),
        .init(cuisine: "Chinese", terms: ["chinese", "china", "sichuan", "szechuan", "kung pao", "dim sum", "char siu"]),
        .init(cuisine: "Japanese", terms: ["japanese", "japan", "sushi", "ramen", "teriyaki", "okonomiyaki", "tonkatsu"]),
        .init(cuisine: "Korean", terms: ["korean", "korea", "bibimbap", "bulgogi", "kimchi", "tteokbokki"]),
        .init(cuisine: "Vietnamese", terms: ["vietnamese", "vietnam", "banh mi", "pho", "bun cha"]),
        .init(cuisine: "Filipino", terms: ["filipino", "philippines", "adobo filipino", "pancit", "sinigang", "lumpia"]),
        .init(cuisine: "Caribbean", terms: ["caribbean", "cuban", "puerto rican", "dominican", "haitian", "trinidadian"]),
        .init(cuisine: "Brazilian", terms: ["brazilian", "brazil", "feijoada", "moqueca"]),
        .init(cuisine: "Latin American", terms: ["latin american", "peruvian", "colombian", "argentinian", "venezuelan", "ceviche peru"]),
        .init(cuisine: "African", terms: ["african", "ethiopian", "nigerian", "ghanaian", "south african", "injera", "jollof"]),
        .init(cuisine: "German", terms: ["german", "germany", "sauerbraten", "spaetzle", "schnitzel german"]),
        .init(cuisine: "British", terms: ["british", "english cuisine", "fish and chips", "toad in the hole"]),
        .init(cuisine: "Irish", terms: ["irish", "ireland", "colcannon", "boxty"]),
        .init(cuisine: "Eastern European", terms: ["eastern european", "polish", "ukrainian", "hungarian", "romanian", "pierogi", "goulash"]),
        .init(cuisine: "BBQ", terms: ["barbecue", "bbq", "barbeque", "smoked brisket"]),
        .init(cuisine: "American", terms: ["american cuisine", "all american", "american classic"]),
        .init(cuisine: "Fusion", terms: ["fusion cuisine", "fusion recipe", "fusion food"]),
    ]

    static let canonicalCuisines = Set(rules.map(\.cuisine))

    static func infer(from evidence: Evidence) -> String? {
        let metadata = normalizedHaystack(evidence.metadata)
        let source = normalizedHaystack(evidence.source)
        let title = normalizedHaystack([evidence.title])
        let summary = normalizedHaystack([evidence.summary])
        let ingredients = normalizedHaystack(evidence.ingredients)

        var ranked: [(index: Int, cuisine: String, score: Int)] = []
        for (index, rule) in rules.enumerated() {
            var score = 0
            for term in rule.terms.map(normalize).filter({ !$0.isEmpty }) {
                if metadata.contains(" \(term) ") { score += 12 }
                if title.contains(" \(term) ") { score += 9 }
                if source.contains(" \(term) ") { score += 7 }
                if summary.contains(" \(term) ") { score += 3 }
                if ingredients.contains(" \(term) ") { score += 1 }
            }
            if score >= 7 { ranked.append((index, rule.cuisine, score)) }
        }
        return ranked.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
        }.first?.cuisine
    }

    static func infer(for recipe: UserRecipe) -> String? {
        guard recipe.cuisine.nilIfBlank == nil else { return nil }
        return infer(from: evidence(for: recipe))
    }

    static func evidence(for recipe: UserRecipe) -> Evidence {
        Evidence(
            title: recipe.title,
            summary: recipe.description,
            metadata: recipe.tags + (recipe.categories ?? []),
            source: [recipe.sourceName ?? "", recipe.sourceURL ?? ""],
            ingredients: recipe.ingredients.map(\.name)
        )
    }

    static func infer(for recipe: RecipeDraft) -> String? {
        guard recipe.cuisines.cleanedUnique().isEmpty else { return nil }
        return infer(from: Evidence(
            title: recipe.title,
            summary: recipe.summary ?? "",
            metadata: recipe.categories + recipe.keywords,
            source: [recipe.source.attribution, recipe.source.host, recipe.source.canonicalURL ?? recipe.source.url],
            ingredients: recipe.ingredientSections.flatMap(\.items).map { $0.name ?? $0.raw }
        ))
    }

    private static func normalizedHaystack(_ values: [String]) -> String {
        " " + normalize(values.joined(separator: " ")) + " "
    }

    private static func normalize(_ value: String) -> String {
        let characters = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
        return String(characters)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
