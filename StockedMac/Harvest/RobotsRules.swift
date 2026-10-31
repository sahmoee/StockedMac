// RobotsRules.swift — an original, Foundation-only robots.txt reader (RFC 9309).
//
// Used by RobotsPolicy for every page and sitemap the Harvester crawls when a source
// requires robots compliance. Kept dependency-free so scripts/test-robots-rules.swift
// can verify it natively. Supports user-agent groups, Allow/Disallow, `*` wildcards,
// `$` end anchors and longest-match precedence (ties resolve to Allow).

import Foundation

nonisolated struct RobotsRules: Sendable, Equatable {
    struct Rule: Sendable, Equatable {
        let allow: Bool
        let pattern: String
    }

    let rules: [Rule]

    static let allowAll = RobotsRules(rules: [])
    static let disallowAll = RobotsRules(rules: [Rule(allow: false, pattern: "/")])

    /// The Harvester's own product token. Publishers can address it directly.
    static let productToken = "stockedharvester"

    /// Parses a robots.txt body and keeps only the group that applies to this crawler:
    /// the most specific user-agent token contained in our user agent (or our product
    /// token), otherwise the `*` group. Multiple groups for the same token are merged.
    static func parse(_ text: String, userAgent: String) -> RobotsRules {
        let agent = userAgent.lowercased()
        var groups: [(agents: [String], rules: [Rule])] = []
        var currentAgents: [String] = []
        var currentRules: [Rule] = []
        var lastWasAgent = false

        func flush() {
            if !currentAgents.isEmpty { groups.append((currentAgents, currentRules)) }
            currentAgents = []
            currentRules = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let colon = line.firstIndex(of: ":") else { continue }
            let field = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch field {
            case "user-agent":
                if !lastWasAgent { flush() }
                currentAgents.append(value.lowercased())
                lastWasAgent = true
            case "allow", "disallow":
                lastWasAgent = false
                guard !currentAgents.isEmpty else { continue }
                // An empty Disallow means "allow everything" and adds no rule.
                guard !value.isEmpty else { continue }
                currentRules.append(Rule(allow: field == "allow", pattern: value))
            default:
                // Sitemap, crawl-delay and unknown fields never end a group of agents
                // (RFC 9309 §2.2); they simply carry no access rule here.
                if field != "sitemap" { lastWasAgent = false }
            }
        }
        flush()

        var bestToken: String?
        for group in groups {
            for token in group.agents where token != "*" && !token.isEmpty {
                if agent.contains(token) || productToken.contains(token) || token.contains(productToken) {
                    if token.count > (bestToken?.count ?? 0) { bestToken = token }
                }
            }
        }
        let selected = bestToken ?? "*"
        let rules = groups.filter { $0.agents.contains(selected) }.flatMap(\.rules)
        return RobotsRules(rules: rules)
    }

    /// `path` is the percent-encoded path plus an optional `?query`.
    func isAllowed(path rawPath: String) -> Bool {
        let path = rawPath.isEmpty ? "/" : rawPath
        if path == "/robots.txt" { return true }
        var best: (length: Int, allow: Bool)?
        for rule in rules where Self.matches(pattern: rule.pattern, path: path) {
            let length = rule.pattern.count
            if let current = best {
                if length > current.length || (length == current.length && rule.allow && !current.allow) {
                    best = (length, rule.allow)
                }
            } else {
                best = (length, rule.allow)
            }
        }
        return best?.allow ?? true
    }

    /// Prefix match with `*` (any run of characters) and a trailing `$` end anchor.
    static func matches(pattern: String, path: String) -> Bool {
        var pattern = pattern
        let anchored = pattern.hasSuffix("$")
        if anchored { pattern.removeLast() }
        let pieces = pattern.components(separatedBy: "*")
        var cursor = path.startIndex
        for (index, piece) in pieces.enumerated() {
            if index == 0 {
                guard path.hasPrefix(piece) else { return false }
                cursor = path.index(path.startIndex, offsetBy: piece.count)
                continue
            }
            if piece.isEmpty { continue }
            let isLast = index == pieces.count - 1
            if isLast && anchored {
                // The final piece must end the path, after the current cursor.
                guard path[cursor...].hasSuffix(piece) else { return false }
                return true
            }
            guard let found = path.range(of: piece, range: cursor..<path.endIndex) else { return false }
            cursor = found.upperBound
        }
        return anchored ? cursor == path.endIndex || pieces.last?.isEmpty == true : true
    }
}
