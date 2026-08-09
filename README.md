# Build 103 (4.43) — Recipes, not category pages

**Mac only.** No worker or iOS change. Applied directly to
`Documents/Stocked Mac/StockedMac/`.

Browse looked stuck: the Activity feed spammed "Category page — found N recipe links"
for minutes on end, the import dashboard sat at 0 Imported the whole time, and the
Categories tab filled up with roundup/listicle posts ("40 Favorite Winter Appetizers",
"Nine Favorite Things 54…") that never resolved into anything importable. Both are fixed.

---

## What was actually happening

Sites like Half Baked Harvest publish collection/roundup posts that look exactly like a
normal recipe URL — no `/category/` in the path, nothing to catch at discovery time.
Only when Stocked actually opened one did it learn it wasn't a recipe, and often it
linked to ANOTHER roundup post, not a dish. The mining code had a one-generation limit
(added deliberately, after an earlier build turned 288 candidates into a 1,662-URL
snowball) — so the first roundup got mined, but a roundup found INSIDE that roundup was
just dropped as a dead end. On a source with several layers of nested collection posts,
that meant candidate after candidate got opened, remined, and dropped — with real recipes
never actually reached, and each hop logging its own Activity line, which is what made it
look like an infinite loop.

## What changed

1. **Mining now recurses, bounded by depth instead of generation count.** Each mined
   link carries a hop-count from its original discovered URL (`HarvestModel.mineDepth`).
   A link found via mining is mined again if it also turns out to be a category page —
   up to 4 hops deep — instead of stopping dead after the first hop. Nested
   roundup-of-roundup chains now resolve down to real recipes automatically, in the
   background, the way discovery and import already work.
2. **One roll-up Activity line per pass, not one per page.** `finishImportRun` now logs
   a single "Opened N category pages in the background, finding M recipe links" summary
   (plus a note if the depth limit was hit) instead of a separate entry for every hub
   page mined. The Activity feed reads as recipes found, not pages visited.

## Installing

1. Files are already in `StockedMac/` — nothing to copy.
2. Build Settings: `MARKETING_VERSION = 4.43`, `CURRENT_PROJECT_VERSION = 103`.
3. Try it: run a source that publishes nested roundup posts (Half Baked Harvest is a
   good stress test) and watch the Activity feed — it should show occasional roll-up
   mining summaries and, within a few passes, actual "Imported <title>" lines, not an
   endless stream of category-page entries.

Files changed vs Build 102: `Harvest/HarvestModel.swift` (`mineDepth` tracking in
`record()`, roll-up logging in `finishImportRun()`), `Core/MacBuildConfig.swift`.

## Verification done here

Brace-balance checked (0 net change in nesting). Traced that `mineDepth` persists for
the session the same way `sessionMinedSet` already did (no new reset path needed), and
that `persistMinedLinks` still runs on every mined page regardless of depth, so the
Categories tab keeps seeing everything even once the depth limit stops further
auto-expansion — nothing that was found is lost, it just stops auto-chaining. Confirmed
the other `CompanionError.listingPage` catch site (`importPage`, the in-browser
single-click import) is a separate, low-frequency manual path and was left unchanged on
purpose. **No Swift compiler here — the real build is Xcode (⌘B).**
