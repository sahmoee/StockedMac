# Build 94 (4.34) — the sitemap fix, and the Browse redesign

**Mac delta only.** No worker or iOS change. The full `StockedMac/` folder is included
(Builds 91–93 files with 94 on top) — copy this one package and you're current.

---

## Why every site stuck on "Reading sitemaps"

Four compounding causes, all fixed:

1. **No request timeout.** The HTTP client used the 60-second default, so one slow or
   stalling site parked the run for a minute per request. Requests now time out at 20 s
   (45 s for the whole transfer), set at both the session and per-request level.
2. **Unbounded recursion through sitemap indexes.** Food Network's `sitemap.xml` is an
   index of hundreds of child sitemaps; the old engine visited every one, sequentially,
   with polite delays between — hours of "Reading sitemaps, 0 found". The walk is now
   breadth-first against ONE budget for the whole run (6/15/40/100 files by speed),
   visits recipe-smelling children first (media/video/author/tag sitemaps go last), and
   stops early once the candidate cap is reached.
3. **Gzipped sitemaps read as garbage.** Large sites ship children as `.xml.gz`; those
   decoded to nothing, hence "0 found" even after fetching. The engine now detects the
   gzip magic bytes and inflates (gzip header parse + raw-DEFLATE via Compression).
4. **No fallback.** A site whose sitemap is blocked or useless ended the run at zero.
   On Auto, the engines now chain — sitemaps → category pages → feeds — until one finds
   recipes, and the session notes say which engine won and what was skipped. A forced
   method still runs alone.

Progress is also honest now: the phase reads "Reading sitemaps (3/15)" and ticks per
file, with queued counts, instead of sitting at "0 pages" while working.

## The Browse redesign

The screenshot's problems — "Speed" overlapped by the segmented control, divider-soup on
the left, acres of empty space on the right — are gone:

- **Cards, not dividers.** Sources, Crawler, Verification, Queue, Images and Cloud cache
  are each a proper card in a scrolling 396-pt column.
- **Labels above controls, everywhere.** Method and Speed have their captions on top and
  their pickers full-width, so nothing can overlap at any window size. Explanatory text
  wraps under each control.
- **Pause moved out of the way** — a toolbar button, plus a banner across the top only
  while paused.
- **A real activity pane.** Stats up top; while browsing, a Browsing card with a linear
  progress bar, the current URL, and pages-read / queued / recipes-found counts; then
  failure card (with Retry), last-session card, history, and activity log. When there is
  truly nothing yet, a designed empty state ("Ready to browse") instead of vacancy.
- Queue editor, bulk verify, image tools and cloud sync all kept, one card each.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`.
2. Build Settings: `MARKETING_VERSION = 4.34`, `CURRENT_PROJECT_VERSION = 94`.
3. Try Food Network again — expect "Reading sitemaps (n/15)" ticking, then candidates;
   or, if its sitemap resists, a note that category pages took over.

Files changed vs Build 93: `Harvest/HarvestInfrastructure.swift` (timeouts),
`Harvest/HarvestTypes.swift` (sitemap file budget), `Harvest/HarvestServices.swift`
(BFS walk, gzip, prioritization, engine chaining, expansion refactor),
`Views/MacBrowseView.swift` (full redesign), `Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). The gzip path was
desk-checked against the gzip spec (header flags FEXTRA/FNAME/FCOMMENT/FHCRC, raw
DEFLATE payload, `COMPRESSION_ZLIB` = raw DEFLATE in Apple's Compression). The BFS
budget math was traced for index-of-indexes, cancel mid-walk, and cap-hit cases.
**No Swift compiler here — the real build is Xcode.**
