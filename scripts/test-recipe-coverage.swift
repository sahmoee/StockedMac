import Foundation

// Minimal structural dependencies for this standalone taxonomy/priority executable.
// The full Mac target separately compiles the production HarvestTypes definitions.
struct DiscoveredLink { var url: String; var title: String? }
extension Array where Element == String {
    func cleanedUnique() -> [String] {
        var seen = Set<String>()
        return compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && seen.insert(trimmed.lowercased()).inserted ? trimmed : nil
        }
    }
}

@main struct RecipeCoverageChecks {
    static func main() throws {
        let plan = RecipeCoveragePlan.bootstrap
        let values = ["old-first", "old-second", "jamaicanfoodsandrecipes.com/chicken", "jamaican-rice", "old-third"]
        let prioritized = plan.prioritized(values) { [$0] }
        precondition(prioritized.first == values[2])
        precondition(prioritized[1] == values[0], "Fair oldest slot retained")
        precondition(Set(prioritized) == Set(values) && prioritized.count == values.count)
        precondition(plan.score(["American jerky"]) == 0)
        let full = RecipeCoveragePlan.build(evidence: Array(repeating: ["Jamaican", "chicken"], count: 12))
        precondition(!full.rules.contains { $0.id.hasPrefix("qa-0135") })
        precondition(full.rules.contains { $0.id == "cuisines-cultures.korean" })
        let encoded = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(RecipeCoveragePlan.self, from: encoded)
        precondition(decoded.prioritized(values) { [$0] } == prioritized)
        precondition(RecipeBrowseTaxonomy.categories(in: "Cuisines & cultures").contains { $0.name == "Jamaican" })
        let empty = RecipeCoveragePlan(rules: [])
        precondition(empty.prioritized(values) { [$0] } == values)
        let start = Date()
        _ = full.prioritized((0..<2_000).map { "https://example.com/recipe-\($0)" }) { [$0] }
        print("Passed 9 coverage checks; 2,000-URL ordering: \(Int(Date().timeIntervalSince(start) * 1000)) ms.")
    }
}
