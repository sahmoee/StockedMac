import Foundation
@main struct CSVGuardChecks {
    static func main() {
        func unquote(_ value: String) -> String {
            guard value.first == "\"", value.last == "\"" else { return value }
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
        }
        let cells = ["=SUM(A1)", "+12", "-recipe", "@lookup", "\tformula", "\r\nrecipe", "'Nduja", "'=literal", "''literal", "normal", "comma,quoted\"\rline"]
        for cell in cells {
            let encoded = unquote(MacCSVInterchange.escape(cell))
            precondition(MacCSVInterchange.unguard(encoded) == cell)
        }
        precondition(MacCSVInterchange.unguard("'Nduja") == "'Nduja")
        print("12 CSV guard regression checks passed")
    }
}
