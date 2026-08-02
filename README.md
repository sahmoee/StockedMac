# Build 95 (4.35) — importing that doesn't take no for an answer

**Mac delta only.** No worker or iOS change. Full `StockedMac/` folder included
(Builds 91–94 with 95 on top) — copy this one package and you're current.

---

## Why everything failed

Two compounding causes, visible in your screenshot:

1. **The user agent.** Since Build 90 the crawler introduced itself as
   `Mozilla/5.0 (…) AppleWebKit/537.36` — truncated, no browser token. Food Network's
   CDN (and most big-site bot walls) answers that UA with a challenge page containing
   no recipe at all, which the parser then honestly reported as "No schema.org/Recipe
   JSON-LD found", 288 times.
2. **One parser.** JSON-LD was the only local engine; any page without it (or any bot
   wall) was a dead end. ("Python worker: not available" is expected — that engine
   doesn't ship in this build.)

## What Build 95 does about it

- **Identifies as Safari** (a real, current UA). A one-time migration updates existing
  installs still on the old string. Presets in the Crawler card: Safari / Chrome /
  Honest bot.
- **Parser chain, four engines deep:** JSON-LD → schema.org **microdata** →
  **heuristic layout reconstruction** (og: tags + ingredient/step scraping; confidence
  capped at 0.55 so it can never auto-approve) → the Worker (when configured). Engines
  fill each other's gaps via the existing merge.
- **WebKit fallback.** If the plain fetch looks like a bot wall — or parsing still
  fails — the page is loaded in an invisible WebKit view and the *rendered* HTML is
  parsed, which is what defeats JS-hydrated and challenge-gated sites. Toggleable;
  such imports carry a "Loaded with the built-in browser" note.
- **Honest errors.** A bot-walled page now says so ("The site is blocking automated
  access…") instead of blaming JSON-LD, and repeated identical log lines collapse to
  one entry with a ×N counter.

## Not running by default

Browsing now **queues**; importing is your explicit button. The primary action reads
"Browse" and fills the queue — it only reads "Browse & Import" when you've switched
*Auto-verify & approve* on, so the label always tells the truth. A one-time migration
turns auto-import off for existing installs (flip it back on in Verification if you
liked it).

## The in-app browser (WebKit, https)

Toolbar → **Open browser**: a real WebKit view with an address bar. Follow links,
land on a recipe, press **Import this page** (same pipeline as every import) or
**Add to queue**. Every row in the new failures panel has **Open**, pre-filled with
that URL — so a page the crawler can't have, you can still take by hand.

## Ten features added

1. In-app WebKit browser panel — any https page, viewable and importable.
2. Automatic WebKit-rendered fetch fallback for blocked and JS-rendered pages.
3. schema.org **microdata** parser (second local engine).
4. **Heuristic HTML** parser (third engine; review-only confidence).
5. **Import failures panel** — every failed URL with its reason, kept, not scrolled away.
6. **Retry all** failures in one press; per-row **Open** in the built-in browser.
7. **Last import summary** card (imported · auto-approved · failed).
8. **User-agent presets** (Safari / Chrome / Honest bot) in the Crawler card.
9. **Import spacing throttle** (0–30 s between imports) for extra politeness.
10. **Clear pauses** quick action — rate-limit pauses and daily counters, one click.

## Twenty improvements

1. Modern Safari UA as the default. 2. One-time settings migration (revision 2) — your
other preferences survive untouched. 3. Auto-import off by default; nothing runs on its
own. 4. Log de-duplication (×N counters) — walls of red are gone. 5. Bot walls named in
errors instead of misreported as missing JSON-LD. 6. Heuristic confidence capped below
every auto-approve threshold. 7. The four-engine chain merges missing fields across
engines. 8. Failures capped at 50 and actionable. 9. WebKit imports tagged in the
draft's warnings. 10. The import summary persists until the next run starts.
11. Rendered retry happens once per URL — no loops. 12. The hidden renderer is
serialized, 18 s-capped, and torn down after each page. 13. The visible browser's
address bar follows in-page navigation. 14. Its Import button disables while a run is
active. 15. og:title/og:image/og:description used as fallbacks by both new parsers.
16. Scraped text gets entity decoding and whitespace collapse. 17. Auto-approved count
shown in the run summary. 18. Browse/Import button labels always match behavior.
19. Failure rows open the exact URL pre-filled. 20. Import spacing applies between
scheduled URLs without slowing the first batch.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`.
2. Build Settings: `MARKETING_VERSION = 4.35`, `CURRENT_PROJECT_VERSION = 95`.
3. Launch once (watch Activity note the new defaults), then press **Import 288 URLs** —
   with the Safari UA and the four-engine chain, Food Network parses.

Files changed vs Build 94: `Harvest/HarvestTypes.swift`, `Harvest/HarvestServices.swift`
(parsers, blocked detection), `Harvest/CrawlCoordinator.swift` (chain + WebKit retry),
`Harvest/HarvestModel.swift` (migration, failures, spacing, log dedupe),
`Harvest/WebKitRenderer.swift` (new), `Views/MacBrowserPanel.swift` (new),
`Views/MacBrowseView.swift`, `Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). Regex escaping in the
two new parsers desk-checked (Swift string → regex layer). WKNavigationDelegate
conformances marked `@preconcurrency` for the MainActor-isolated classes. The migration
only fires below revision 2 and only rewrites the two migrated fields.
**No Swift compiler here — the real build is Xcode.**
