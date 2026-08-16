import Foundation

/// Removes crawler/database identifiers without damaging quantities that belong to a
/// recipe name ("7 Layer Dip", "15-Minute Pasta", "Steak for 2", or a four-digit year).
nonisolated enum RecipeTitlePolicy {
    static func cleaned(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        value = value.replacingOccurrences(
            of: #"(?:\s+|\s*[-–—|:]\s*)(?:recipe\s+id\s*|id\s*)?\d{5,}\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|:")))
    }
}
