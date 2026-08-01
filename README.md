# Build 91 (4.31) — the Browse section

**This package touches two projects: the Mac app (primary) and the unified worker (one new
file, one revised file). No iOS file is included or required.** The iOS app stays on its own
build; two optional read-only worker routes are waiting for it whenever it wants them.

Which project is which:

| Folder in this package | Copies into | Project |
|---|---|---|
| `StockedMac/` | `Documents/Stocked Mac/StockedMac/` | **Stocked for Mac** (macOS only) |
| `worker/` | `Documents/worker/` | **Unified Cloudflare Worker** |
| `sync/` | see inside each file | Cross-project trackers for all three folders |

---

## Why "No sources loaded" happened

The 100-site catalog existed on disk (`default-sources.json`) but reached the app only as a
*bundled resource*. On trees where the synchronized folder didn't copy the JSON into the app
bundle, `SourceRegistry` found no local file, no bundled file, and quietly loaded nothing —
the Browse panel then said "No sources loaded" and `resetSources` put "Action failed" in the
footer, exactly what your screenshot shows.

Three fixes, layered:

1. **The catalog is now compiled into the app** (`DefaultSourceCatalog.swift`) — the chain is
   local `sources.json` → bundled JSON → embedded constant. It can no longer be missing.
2. **An empty local `sources.json` no longer wins.** An interrupted first launch used to leave
   a valid `[]` on disk that shadowed the catalog forever.
3. **Decoding is tolerant** — per-element (one bad entry costs one entry, not the catalog) and
   per-field (old files missing new keys still load).

The catalog is the top 50 American recipe sites plus the top 50 worldwide, grouped that way
in the new dropdown.

---

## The new Browse section

`MacBrowseView.swift` adds **Browse** to the sidebar under Household (⌘B). Every import
function moved there from Harvest: the source dropdown (grouped: Recent / American Top 50 /
Worldwide Top 50 / Custom, searchable by name, tag or domain, with health dots), Browse &
Import, Queue only, Next in rotation, the queue editor, auto-verify, and the discovery
report. Harvest keeps the review library and gained review tools of its own.

### Ten new features

1. **Browse sidebar section** — the full import pipeline in one place, under Household.
2. **Pause / Resume everything** — one gate parks browsing, imports and image downloads
   mid-run without cancelling; Resume continues exactly where it stopped.
3. **Bulk verify** — checks every queued URL against the recipe-page detector and removes
   the ones that aren't recipes (network failures keep their URL). Optional
   *verify before import* runs it automatically.
4. **Auto-rotate** — browses N sources back to back (count is a stepper, 1–10), chaining
   after each source's import finishes.
5. **Image gate** — "Require an image before a recipe reaches the kitchen" is now a visible,
   enforced setting: no auto-approval and no hand-over without image bytes on disk, so the
   iOS app never receives a pictureless recipe.
6. **Fetch missing images** — one button retries every failed image download; also runs
   automatically after each import run (toggleable).
7. **Cloud cache sync** — approved recipes and their images push to the Worker
   (`POST /harvest/cache`, `POST /harvest/image`), manually or automatically on approval.
8. **Session history** — the last 20 discovery reports are listed and restorable with one
   click, including finishing a stopped session's unchecked links.
9. **Bulk approve / reject** in Harvest — act on everything the current filter shows.
10. **Missing-image filter + thumbnails** in Harvest — see exactly which drafts the phone
    would reject, with a cached thumbnail per row and a "no image" badge.

### Ten improvements

1. Embedded source catalog — "No sources loaded" is structurally impossible now.
2. Empty/corrupt `sources.json` recovery (falls through to the catalog instead of nothing).
3. Tolerant `SourceProfile` and `AppSettings` decoding — old files load, new keys default;
   your saved settings survive this upgrade instead of resetting.
4. Image validation — downloads must decode as a real image ≥ 120 px on the short edge;
   HTML error pages saved as `.jpg` no longer count as photos.
5. Content-addressed image files — the same image URL reuses the bytes already on disk
   (SHA-256 filename) instead of a fresh UUID copy per import.
6. Per-source crawl delay — the rate limiter honours each site's `minimumDelaySeconds`
   instead of a hardcoded 2 s for everybody.
7. Auto-approval respects the image gate (no more approve-then-silently-drop).
8. Settings edited in Browse actually save (`scheduleSettingsSave` is wired to every toggle).
9. Sidebar badges for Browse (queued URLs) and Harvest (awaiting review).
10. Kitchen home card "Browse recipes" now opens Browse; proper Accept headers on image
    requests; queue/report/pause states all surfaced inline instead of hiding in logs.

---

## Worker changes (`worker/`)

New `src/apps/stocked/src/harvest.js` + four routes wired in `index.js`
(version → `2026-08-01.1`, capability `harvest-cache`):

| Route | What |
|---|---|
| `POST /harvest/cache` | Upsert ≤ 50 recipes into KV (`harvest:recipe:<id>` + index) |
| `POST /harvest/image` | Store one image — R2 (`env.MEDIA`) when bound, else KV base64, ≤ 1 MB |
| `GET /harvest/recipes` | The whole cache, 10-min edge cache |
| `GET /harvest/img/<id>.jpg` | One image, 30-day edge cache |

All behind the existing `X-Stocked-Key` gate; writes rate-limited like other routes. No new
bindings required (uses `CROWD`; uses `MEDIA` R2 automatically if you ever bind it).
**About cPanel:** the worker retired the cPanel origin (see `content.js`); this cache is its
successor — same job, on infrastructure that is actually still in the loop. Deploy with
`wrangler deploy` as usual.

---

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`, keeping the folder
   structure. Synchronized folders pick up the four new Swift files automatically.
   `default-sources.json` (unchanged content) stays where it is.
2. Copy `worker/src/apps/stocked/index.js` and `worker/src/apps/stocked/src/harvest.js`
   into `Documents/worker/`, then `wrangler deploy`.
3. Copy each file in `sync/` to the folder named at the top of that file.
4. Set the Mac target's version in Build Settings:

   ```
   MARKETING_VERSION       = 4.31
   CURRENT_PROJECT_VERSION = 91
   ```

   The iOS target keeps its own numbers; nothing on the phone changes.

---

## The things not to refactor

- **Hand-over still goes through `MacHarvestBridge.add` → `MacKitchenStore.addRecipe`**, and
  removals through the store's delete methods — the household tombstone rules from the
  Build 90 README all still apply.
- The bridge's own `image != nil` guard stays even though the model now gates earlier;
  belt and braces on the "nothing without an image" promise.
- `AppSettings`/`SourceProfile` keep synthesized **encoding**; only decoding is custom.
  Don't add fields without extending both the field list and the tolerant `init(from:)`.
- The Worker's legacy 7 routes, header names and schema versions are untouched.

## Verification done here

Every Swift file brace/paren/bracket-balanced (raw-string aware). Both worker files pass
`node --check`. Every symbol the new code calls was resolved against the staged tree:
`MacTheme.gold/green`, `MacCard`, `MacEmpty`, `MacNavigation.section`,
`HarvestModel`'s stores/actors, `MacWorkerClient.isConfigured`,
`MacBuildConfig.authorizeWorkerRequest`, `JSONCoding`, `URLSafety`, `Hashing.sha256`,
`nilIfBlank`, and the worker's `util.js` exports (`json`, `errJson`, `withCors`,
`background`, `logEvent`). The embedded catalog round-trips through `JSONDecoder` with the
tolerant `SourceProfile` decoder. **There is no Swift compiler here — the real build is
Xcode on your Mac.**
