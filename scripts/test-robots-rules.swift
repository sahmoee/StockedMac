// Native robots.txt check. Compile with the production rules:
//   swiftc -parse-as-library StockedMac/Harvest/RobotsRules.swift \
//          scripts/test-robots-rules.swift -o /tmp/robots && /tmp/robots
import Foundation

@main struct RobotsRulesChecks {
    static let agent = "Mozilla/5.0 (Macintosh) StockedHarvester/1.0"

    static func main() {
        let general = RobotsRules.parse("""
        # comment
        User-agent: *
        Disallow: /private/
        Allow: /private/public-recipe
        Disallow: /*.pdf$
        Disallow: /search?

        User-agent: OtherBot
        Disallow: /
        """, userAgent: agent)
        precondition(general.isAllowed(path: "/recipes/soup"))
        precondition(!general.isAllowed(path: "/private/drafts"))
        precondition(general.isAllowed(path: "/private/public-recipe"), "longer Allow wins")
        precondition(!general.isAllowed(path: "/files/menu.pdf"), "$ anchor")
        precondition(general.isAllowed(path: "/files/menu.pdf?download=1"), "$ anchor needs end of path")
        precondition(!general.isAllowed(path: "/search?q=soup"))
        precondition(general.isAllowed(path: "/robots.txt"))

        let specific = RobotsRules.parse("""
        User-agent: *
        Disallow: /

        User-agent: StockedHarvester
        Disallow: /admin
        """, userAgent: agent)
        precondition(specific.isAllowed(path: "/recipes/soup"), "our own group overrides *")
        precondition(!specific.isAllowed(path: "/admin/login"))

        let shared = RobotsRules.parse("""
        User-agent: GoogleBot
        User-agent: *
        Sitemap: https://example.com/sitemap.xml
        Disallow: /tmp
        """, userAgent: agent)
        precondition(!shared.isAllowed(path: "/tmp/x"), "grouped agents share rules across a Sitemap line")

        let empty = RobotsRules.parse("User-agent: *\nDisallow:\n", userAgent: agent)
        precondition(empty.isAllowed(path: "/anything"), "empty Disallow allows all")

        let tie = RobotsRules.parse("User-agent: *\nDisallow: /page\nAllow: /page\n", userAgent: agent)
        precondition(tie.isAllowed(path: "/page"), "ties resolve to Allow")

        precondition(RobotsRules.matches(pattern: "/a*b*c", path: "/axxbyyc/zz"))
        precondition(!RobotsRules.matches(pattern: "/a*b$", path: "/axxbc"))
        precondition(RobotsRules.matches(pattern: "/a*$", path: "/anything"))
        precondition(!RobotsRules.disallowAll.isAllowed(path: "/"))
        precondition(RobotsRules.allowAll.isAllowed(path: "/x"))
        print("Robots rules checks passed: groups, precedence, wildcards, anchors and fallbacks")
    }
}
