# Build 102 (4.42) — Never empty-handed

**Mac only.** No worker or iOS change. Applied directly to
`Documents/Stocked Mac/StockedMac/`.

A run must always deliver something. Previously, a rate limit, a network drop, or the
user pressing Stop mid-discovery could throw away everything a run had already found —
and a run that only ever surfaced category/hub pages could end with nothing imported at
all. Both are fixed, and importing a single URL directly (no source/category picking) is
now always available.

---

## What changed

1. **Interruptions no longer erase progress.** `DiscoveryEngine.discover` used to let a
   failure on any one engine (429, robots block, network error) or a cancellation
   mid-fetch throw the whole run away — HarvestModel's outer `catch` discarded
   everything, including recipes an earlier engine or earlier mining had already found.
   Now each engine attempt is individually caught: a real error logs a note and the chain
   tries the next engine; a cancellation stops the chain immediately but keeps whatever
   is already in `recipeURLs`/`minedCategories`. `discover()` effectively never throws in
   normal operation anymore — it always returns a report built from what it has.
2. **A real recipe is always the target.** If the whole chain (plus its speed-budgeted
   mining) still ends with nothing confirmed and nothing unverified, the engine keeps
   opening the categories it already knows about — one hub at a time — until a real
   recipe link turns up or every known hub has been tried. A run no longer ends with only
   cached, unmined category tiles and zero importable recipes.
3. **Stop/rate-limit now imports what was found.** Because `discover()` returns instead
   of throwing, HarvestModel's existing confirmed → unverified → queue fallback chain
   runs normally after a stop or a 429, so autopilot (or auto-import) imports whatever was
   gathered up to that point instead of just showing "Browse canceled."
4. **Import from a URL, always.** Find & Import now has a direct URL field ("Or paste a
   recipe URL to import it directly…") wired straight to `importDirect` — importing a
   single link no longer requires picking a source or category first.

## Installing

1. Files are already in `StockedMac/` — nothing to copy.
2. Build Settings: `MARKETING_VERSION = 4.42`, `CURRENT_PROJECT_VERSION = 102`.
3. Try it: paste a recipe URL directly into the new field in Find & Import and press
   Import. Then start a normal Browse run and press Stop partway through — whatever was
   found so far should still come in.

Files changed vs Build 101: `Harvest/HarvestServices.swift` (`DiscoveryEngine.discover`
per-engine error/cancellation handling + guaranteed-recipe fallback mining),
`Harvest/HarvestModel.swift` (`discover()` cancellation-catch message),
`Views/MacBrowseView.swift` (direct URL import field), `Core/MacBuildConfig.swift`.

## Verification done here

`HarvestServices.swift`, `HarvestModel.swift`, and `MacBrowseView.swift` brace-balance
checked (HarvestServices carries its known pre-existing +2 offset from single-character
brace string literals in `balancedJSONObject`, unchanged by this build — the new code
adds a matched do/catch and for-loop only). `MinedCategory.recipeURLs` mutation via array
index confirmed valid (struct, `var` field, `var` array). Traced that `bulkVerifyQueue`
already handled cancellation/network failure gracefully before this build (unchecked URLs
stay queued, mined links are kept) — no change needed there. Traced the stop/autopilot
path end to end: `stopAutopilot()` cancels the discovery Task, `discover()` now returns
normally with partial results instead of throwing, and the existing
confirmed → unverified → queue import logic runs unchanged. **No Swift compiler here —
the real build is Xcode (⌘B).**
