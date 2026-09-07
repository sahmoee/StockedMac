import Foundation

/// Removes crawler/database identifiers without damaging quantities that belong to a
/// recipe name ("7 Layer Dip", "15-Minute Pasta", "Steak for 2", or a four-digit year).
nonisolated enum RecipeTitlePolicy {
    private static let minorWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "of", "on", "or", "the", "to", "via", "with"
    ]
    private static let culinaryAcronyms: [String: String] = [
        "bbq": "BBQ", "blt": "BLT", "pb&j": "PB&J", "diy": "DIY", "ipa": "IPA"
    ]

    static func cleaned(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        value = value.replacingOccurrences(
            of: #"(?:\s+|\s*[-–—|:]\s*)(?:recipe\s+id\s*|id\s*)?\d{5,}\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        value = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|:")))
        return standardizedCase(value)
    }

    /// Alphabetic ordering must not promote quoted/parenthesized titles ahead of A.
    /// Keep meaningful punctuation in the displayed title and ignore it only for order.
    static func sortKey(_ raw: String) -> String {
        let cleaned = cleaned(raw).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let start = cleaned.firstIndex { $0.isLetter || $0.isNumber } ?? cleaned.startIndex
        return String(cleaned[start...])
    }

    private static func standardizedCase(_ value: String) -> String {
        let letters = value.filter(\.isLetter)
        guard !letters.isEmpty else { return value }
        let needsRepair = letters == letters.lowercased() || letters == letters.uppercased()
        guard needsRepair else { return value }
        let words = value.split(separator: " ", omittingEmptySubsequences: true)
        return words.enumerated().map { index, rawWord in
            let lower = rawWord.lowercased()
            if let acronym = culinaryAcronyms[lower] { return acronym }
            if index > 0, index < words.count - 1, minorWords.contains(lower) { return lower }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }
}
