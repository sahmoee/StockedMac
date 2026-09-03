import Foundation

/// Mac-owned discovery hints, NOT recipe classification or eligibility. Shared with
/// the headless server through the existing cache bridge; no recipe/private data.
/// Terms are OR within a group and AND across groups. Every candidate still passes
/// the ordinary parser, image, provenance, approval and publication gates.
nonisolated struct RecipeCoveragePlan: Codable, Sendable {
    struct Rule: Codable, Sendable {
        var id: String
        var groups: [[String]]
        var deficit: Int
        var weight: Int = 1
        func matches(_ text: String) -> Bool {
            groups.allSatisfy { terms in terms.contains { text.contains(" \($0) ") } }
        }
    }
    var schemaVersion = 1
    var generatedAt = Date().timeIntervalSince1970
    var rules: [Rule]
    // STK-89-0135: temporary bootstrap until a measured approved-library snapshot
    // exists. Prioritizes discovery only; never manufactures a "Comfort" tag.
    static var bootstrap: Self { Self(rules: [
        Rule(id: "qa-0135-jamaican", groups: [["jamaican", "jamaica", "jamaicanfoodsandrecipes"]], deficit: 12, weight: 2),
        Rule(id: "qa-0135-jamaican-chicken", groups: [["jamaican", "jamaica", "jamaicanfoodsandrecipes"], ["chicken"]], deficit: 12, weight: 4)
    ]) }
    static func normalize(_ value: String) -> String {
        " " + value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
    }
    /// Index terms once per batch. Testing every category/alias against every URL
    /// blocked the main actor for >1s on a 2,000-link queue in the native regression.
    private struct Matcher {
        var terms: [String: [(rule: Int, group: Int, phrase: String)]] = [:]
        var groupCounts: [Int]
        init(_ rules: [Rule]) {
            groupCounts = rules.map { $0.groups.count }
            for (index, rule) in rules.enumerated() {
                for (group, choices) in rule.groups.enumerated() {
                    for term in choices {
                        guard let first = term.split(separator: " ").first else { continue }
                        terms[String(first), default: []].append((index, group, " " + term + " "))
                    }
                }
            }
        }
        func matches(_ values: [String]) -> [Int] {
            let text = RecipeCoveragePlan.normalize(values.joined(separator: " "))
            var masks: [Int: Int] = [:]
            for word in Set(text.split(separator: " ")) {
                for term in terms[String(word), default: []] where text.contains(term.phrase) {
                    masks[term.rule, default: 0] |= 1 << term.group
                }
            }
            return masks.compactMap { index, mask in mask == (1 << groupCounts[index]) - 1 ? index : nil }
        }
    }
    static func build(evidence: [[String]]) -> Self {
        let groups = ["Cuisines & cultures", "Meals & courses", "Food & dish types", "Cooking methods", "Seasons & lifestyle", "Dietary needs"]
        var rules = groups.flatMap { group in RecipeBrowseTaxonomy.categories(in: group).map {
            Rule(id: $0.id, groups: [$0.terms], deficit: 12)
        }}
        rules += bootstrap.rules
        let matcher = Matcher(rules)
        for values in evidence {
            if Task.isCancelled { return bootstrap }
            for index in matcher.matches(values) where rules[index].deficit > 0 {
                rules[index].deficit -= 1
            }
        }
        return Self(rules: rules.filter { $0.deficit > 0 })
    }
    func score(_ values: [String]) -> Int {
        Matcher(rules).matches(values).reduce(0) { $0 + rules[$1].deficit * rules[$1].weight }
    }
    /// Half the slots favor gaps; half retain the original fair order. No candidate
    /// is removed. Stable ties avoid repeated sorts reshuffling a durable queue.
    func prioritized<T>(_ values: [T], evidence: (T) -> [String]) -> [T] {
        let matcher = Matcher(rules)
        var ranked: [(index: Int, score: Int)] = []
        for index in values.indices {
            let score = matcher.matches(evidence(values[index])).reduce(0) { $0 + rules[$1].deficit * rules[$1].weight }
            if score > 0 { ranked.append((index: index, score: score)) }
        }
        ranked.sort { left, right in
            if left.score == right.score { return left.index < right.index }
            return left.score > right.score
        }
        var used = Set<Int>(), next = 0, result: [T] = []
        for (index, _) in ranked {
            if used.insert(index).inserted { result.append(values[index]) }
            while next < values.count && used.contains(next) { next += 1 }
            if next < values.count { used.insert(next); result.append(values[next]); next += 1 }
        }
        for index in values.indices where used.insert(index).inserted { result.append(values[index]) }
        return result
    }
}
