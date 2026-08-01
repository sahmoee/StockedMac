import Foundation

nonisolated enum SourceBadge: String, Codable, CaseIterable, Sendable {
    case verified = "Verified"
    case estimated = "Estimated"
    case userAdded = "User added"
    case aiParsed = "AI parsed"
    case needsReview = "Needs review"
}

nonisolated enum DishRole: String, Codable, Sendable, CaseIterable {
    case entree
    case side
    case component
    case fullMeal
    case unspecified

    var label: String {
        switch self {
        case .entree: return "Entrée"
        case .side: return "Side"
        case .component: return "Component"
        case .fullMeal: return "Full meal"
        case .unspecified: return "Recipe"
        }
    }
}

nonisolated extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func matches(_ pattern: String, group: Int = 0) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(startIndex..., in: self)
        return expression.matches(in: self, range: fullRange).compactMap { match in
            guard group < match.numberOfRanges,
                  let range = Range(match.range(at: group), in: self) else { return nil }
            return String(self[range])
        }
    }
}

nonisolated func normalizedTitle(_ title: String) -> String {
    title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}
