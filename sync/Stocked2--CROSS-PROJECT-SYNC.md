# CROSS-PROJECT-SYNC — this folder is **Stocked for iOS** (`Documents/Stocked 2`)

> Identification for any chat: this is the **iOS** Xcode project (`Stocked.xcodeproj`,
> with `StockedShareExtension`, `StockedWidgets`, `StockedTests`). The macOS app lives
> in `Documents/Stocked Mac`; the Cloudflare Worker in `Documents/worker`. Every update
> applied to one project must be recorded in the other folders' copies of this file.

## Updates applied elsewhere that concern iOS

### 2026-08-01 — Mac Build 91 (Browse) + worker harvest cache
- **No iOS code change required.** The iOS build and version numbers do not move.
- The Mac app now enforces "no recipe without an image" *before* hand-over, so every
  recipe arriving via household sync from the Mac carries image data or a working
  image URL. Blank-placeholder recipes from Mac imports should stop appearing.
- The worker gained `GET /harvest/recipes` and `GET /harvest/img/<id>.jpg`
  (same `X-Stocked-Key`): a cache of Mac-approved recipes with guaranteed images.
  Optional future adoption — e.g. as a Discover/curated feed source alongside
  `/content/recipes`.
- Shared model lineage: Mac's `Models.swift` / `KitchenMetrics.swift` remain
  byte-identical to iOS as of Mac Build 91; if iOS models move, re-run the diff and
  update `MacBuildConfig.sharedModelLineage`.

### 2026-08-01 — note: Mac Build 92
- Mac-only UI/catalog work (multi-select sources, list import/export, self-heal).
  **No iOS change required**; nothing about sync or the worker contract moved.
