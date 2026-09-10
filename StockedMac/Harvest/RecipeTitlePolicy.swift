import Foundation

/// Removes crawler/database identifiers without damaging quantities that belong to a
/// recipe name ("7 Layer Dip", "15-Minute Pasta", "Steak for 2", or a four-digit year).
nonisolated enum RecipeTitlePolicy {
    /// Recipe lists ask for the same ordering key many times during SwiftUI layout.
    /// Cache the normalized title so a 1,500-row list does not run regular expressions
    /// inside every sort comparison on every view update.
    private nonisolated(unsafe) static let sortKeyCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 10_000
        return cache
    }()
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
        let cacheKey = raw as NSString
        if let cached = sortKeyCache.object(forKey: cacheKey) { return cached as String }
        let cleaned = cleaned(raw).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let start = cleaned.firstIndex { $0.isLetter || $0.isNumber } ?? cleaned.startIndex
        let result = String(cleaned[start...])
        sortKeyCache.setObject(result as NSString, forKey: cacheKey)
        return result
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
