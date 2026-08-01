# CROSS-PROJECT-SYNC — this folder is **Stocked for Mac** (`Documents/Stocked Mac`)

> Identification for any chat: this is the **macOS-only** Xcode project
> (`StockedMac.xcodeproj`, bundle `com.sowens.StockedMac`). The iOS app lives in
> `Documents/Stocked 2` (`Stocked.xcodeproj`). The Cloudflare Worker lives in
> `Documents/worker`. Every update applied to one project must be recorded in the
> other folders' copies of this file.

## Applied updates

### Build 92 (4.32) — source picker & list files — 2026-08-01
- Browse sources dropdown is now a multi-select checklist (search, group All/None,
  health dots); "Browse N sources" visits each selected site in turn.
- Source list maintainable from files: import .txt/.csv (one site per line, "Name | url")
  or .json (full profiles, updates by id); export current catalog as JSON.
- Self-heal: an app that launches with zero enabled+browsable sources restores the
  built-in catalog automatically (custom/imported sources kept); Restore button inline.
- Worker impact: none (Build 91 worker deploy still current). iOS impact: none.

### Build 91 (4.31) — Browse section — 2026-08-01
- New sidebar section **Browse** (under Household, ⌘B): source dropdown grouped
  American Top 50 / Worldwide Top 50 / Custom / Recent, pause-resume for all network
  work, bulk verify, auto-rotate, image gate + recovery, cloud cache sync, session
  history. Harvest reduced to review-only (thumbnails, bulk approve/reject,
  missing-image filter).
- Source catalog now also embedded in code (`DefaultSourceCatalog.swift`); registry
  falls back local → bundled → embedded; tolerant decoding for sources and settings.
- **Requires worker deploy**: talks to `POST /harvest/cache`, `POST /harvest/image`
  (added to the worker the same day — see `Documents/worker/CROSS-PROJECT-SYNC.md`).
  Cloud sync degrades to a clear status message if the worker is older.
- iOS impact: none required. Optional adoption: `GET /harvest/recipes` and
  `GET /harvest/img/<id>.jpg` serve the Mac-approved, image-guaranteed recipe cache.

### Build 90 (4.30) — recipe housekeeping — earlier
- Settings ▸ Data Recipes section; CSV export/remove; retired-source removal.
  No worker or iOS change.
