import Foundation

/// Spreadsheet guards are reversible: double a genuine leading apostrophe,
/// and prefix a formula lead before applying ordinary CSV quoting.
nonisolated enum MacCSVInterchange {
    private static let formulaLeads: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
    private static let needsQuoting: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]

    static func escape(_ raw: String) -> String {
        var value = raw
        if let first = raw.unicodeScalars.first, first == "'" || formulaLeads.contains(first) {
            value = "'" + value
        }
        if value.unicodeScalars.contains(where: { needsQuoting.contains($0) }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func unguard(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.first == "'", let next = scalars.dropFirst().first,
              next == "'" || formulaLeads.contains(next) else { return value }
        return String(value.dropFirst())
    }
}
