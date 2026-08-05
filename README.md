# Build 100 (4.40) — Harvest + Browse, combined and guided

**Mac only.** No worker or iOS change. Applied directly to
`Documents/Stocked Mac/StockedMac/` (no separate package this build).

---

## One section instead of two

Harvest is no longer its own sidebar item — it folded into **Browse**. Browse is now the
single place recipes are found, imported, *and* approved, with a switch at the top:

- **Find & Import** — the guided flow. Pick a source, pick a category, press **Start**.
  One button runs discovery → verification → import → auto-approve.
- **Review** — the old Harvest library, unchanged in what it does: search, filter,
  bulk approve/reject on the left; the full recipe with its Stocked-standards checklist
  on the right. When an import finishes, the "Review N" button drops you straight in.

The sidebar's Browse badge shows how many recipes are **waiting to review** first, and
falls back to how many links are queued. `⌘9` now opens Household; Browse is still `⌘B`.

## Guided by default, everything else tucked away

The default screen is three choices and a button. Every power control now lives behind a
single collapsed **Advanced** panel, grouped:

| Group | What's inside |
|---|---|
| **Discovery** | Prefer direct links, reuse saved results, rotation, source import/export/restore |
| **Crawler** | Method, speed, WebKit fallback, import spacing, user-agent, Python parser test |
| **Verify & import** | Verify-first, standards gate, approval confidence, Verify now, verify batch, queue cap, import batch |
| **Delivery** | Require image, retry images, cloud sync |

## Avoid mining — and when you can't, import it first

Mining (opening a "breakfast" hub and scraping its recipe links) is now a **fallback**,
not the default path:

- New **Prefer direct recipe links** setting (on by default). When a site's sitemap or
  feed already hands over enough real recipe URLs (≥ 12), its category/listing pages are
  left unopened. The report says so: *"8 category pages skipped — 40 direct recipe links
  already found (mining avoided)."*
- When mining *is* the only way in, the recipes it surfaces **lead the queue**. Import-time
  hub refusals and bulk-verify both **prepend** mined links, and bulk-verify now orders
  `mined + verified + remainder`, so mined recipes are verified and imported **first** —
  in the Automatic workflow they go in immediately instead of waiting for a press.
- The Build 98/99 convergence rules still hold: one generation of mining, session-wide
  dedupe, queue cap. The queue strictly shrinks as it drains, so this can't snowball.

## Installing

1. Files are already in `StockedMac/` — nothing to copy this build.
2. Build Settings: `MARKETING_VERSION = 4.40`, `CURRENT_PROJECT_VERSION = 100`.
3. Try it: open **Browse**, pick one source, press **Start** with "Automatic" selected,
   and watch the phases run and the drafts appear in **Review**. Then open **Advanced**
   and confirm every old control is still there.

Files changed vs Build 99: `Harvest/HarvestTypes.swift` (new `preferDirectRecipes`,
settings revision 4), `Harvest/HarvestModel.swift` (`prependImportURLs`, mined-first
import, migration), `Harvest/HarvestServices.swift` (skip listing expansion when direct
delivers), `Views/MacBrowseView.swift` (rebuilt: Find/Review panes, Advanced),
`Views/MacKitchenViews.swift` (`MacHarvestView` removed, `HarvestDraftDetail` shared),
`Views/MacRootView.swift` and `Views/MacCommands.swift` (section removed, nav rewired),
`Core/MacBuildConfig.swift`.

## Verification done here

All changed Swift files brace-balanced (MacBrowseView 558/558, MacKitchenViews 149/149).
Project-wide grep confirms zero remaining `.harvest` / `MacHarvestView` references in the
live tree, so every `MacSection` switch stays exhaustive. `AppSettings` got its new key in
**both** `CodingKeys` and the tolerant `init(from:)`, so the toggle persists. The mined
import loop was traced for convergence (session-set dedupe, one-generation cap, strict
queue drain, already-imported early-return). **No Swift compiler here — the real build is
Xcode (⌘B).**
