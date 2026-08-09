# CROSS-PROJECT-SYNC — this folder is **Stocked for Mac** (`Documents/Stocked Mac`)

> Identification for any chat: this is the **macOS-only** Xcode project
> (`StockedMac.xcodeproj`, bundle `com.sowens.StockedMac`). The iOS app lives in
> `Documents/Stocked 2` (`Stocked.xcodeproj`). The Cloudflare Worker lives in
> `Documents/worker`. Every update applied to one project must be recorded in the
> other folders' copies of this file.

## Applied updates

### 2026-08-06 — iOS now pulls the harvest cache (no Mac change)
- **No Mac app change; recorded here because it completes the Mac→cloud→iOS recipe path.**
  Since Build 91 the Mac has pushed approved harvested recipes to the Worker
  (`HarvestCloudSync.swift` → `POST /harvest/cache` + `/harvest/image`); since the 2026-08-05
  Worker fix those pushes actually persist. As of 2026-08-06 the **iOS** app finally reads them
  back: a new `Stocked/HarvestRecipeSync.swift` GETs `/harvest/recipes` on launch, on every
  foreground, and every 15 minutes, and folds each recipe into its on-device `RecipeDatabase`.
- **What this means for Mac work:** the `POST /harvest/cache` payload shape in
  `HarvestCloudSync.payload(for:)` is now a live contract that iOS decodes field-by-field
  (`id, title, description, cuisine, tags, ingredients:[{name,amount}], instructions:[…],
  sourceURL, attribution, confidence, image, imageURL, servings, prepTime, cookTime`). Changing
  or renaming those fields will silently drop data on iOS — keep it additive, and mirror any
  change in `Documents/Stocked 2/CROSS-PROJECT-SYNC.md`.
- iOS uses each recipe's `attribution` as the source name (falls back to "Stocked Kitchen"),
  so keep attribution honest and free of the retired "Sowens"/"kaggle" fragments the iOS
  blocklist rejects. Recipes are guaranteed to carry an image by the Mac before push, which is
  what makes them presentable in the iOS pool. See `Documents/worker/CROSS-PROJECT-SYNC.md` and
  the iOS file's 2026-08-06 entry for details.

### Build 103 (4.43) — Recipes, not category pages — 2026-08-05
- **Root cause of the "stuck in a category loop" report:** sites that nest roundup posts
  inside other roundup posts (a "40 favorite appetizers" post linking to a "9 favorite
  things" post linking to the actual dish) hit a one-generation mining limit that had
  been added deliberately (an earlier build turned 288 candidates into a 1,662-URL
  snowball). That limit stopped expanding after the first hop and dropped the rest as
  dead ends — so candidates kept getting opened, mined, and discarded without ever
  reaching a real recipe, each hop spamming its own Activity line.
- **Fixed:** `HarvestModel` now tracks a per-link hop count (`mineDepth`) instead of a
  flat generation flag — mining recurses automatically in the background up to 4 hops
  deep before it stops, so nested roundup chains resolve down to real recipes instead of
  dead-ending. `finishImportRun` logs one roll-up Activity line per import pass ("Opened
  N category pages in the background, finding M recipe links") instead of one entry per
  page mined — the feed reports recipes found, not pages visited.
- Files changed vs Build 102: `Harvest/HarvestModel.swift`, `Core/MacBuildConfig.swift`.
- No settings migration, no worker/iOS impact.

### 2026-08-05 — Worker fix: /harvest/* routes now actually exist (no Mac code change)
- **No Mac app change; this is a worker-only fix, recorded here because it directly
  concerns Mac's cloud sync.** Confirmed the app already talks to the correct unified
  worker: `MacBuildConfig.receiptWorkerURL = "https://api.sowensstudios.com"` is the
  same custom domain iOS uses, the `X-Stocked-Key` header name and `STOCKED_SHARED_KEY`
  secret name match exactly, and the unified worker's default (no-prefix) routing sends
  every Mac request to the `stocked` app module — same as iOS today.
- **Found real drift while checking this:** `HarvestCloudSync.swift`'s `POST
  /harvest/cache`, `POST /harvest/image`, and the `GET /harvest/recipes` /
  `GET /harvest/img/<id>.jpg` reads documented since Build 91 were never actually
  implemented on the worker — not in the old standalone worker, not after the merge.
  Every push since Build 91 has been silently failing (422 "Unrecognized request", no
  UI error surfaced). See `Documents/worker/CROSS-PROJECT-SYNC.md` 2026-08-05 entry for
  the full fix — `src/apps/stocked/src/harvest.js` now exists for real, wired into
  `index.js`, same contract Mac's code already expects. No Mac-side change needed; cloud
  sync should just start working on the next run.

### Build 102 (4.42) — Never empty-handed — 2026-08-05
- **Interruptions no longer erase progress.** `DiscoveryEngine.discover` (Harvest
  Services) used to let a failure on any one engine (429, robots block, network error) or
  a mid-fetch cancellation throw the whole run away, discarding recipes an earlier engine
  or earlier mining had already found. Each engine attempt in the chain is now wrapped in
  its own do/catch: a real error logs a note and the chain tries the next engine; a
  cancellation stops the chain immediately but keeps whatever is already gathered.
  `discover()` effectively never throws in normal operation now — it always returns a
  report built from what it has.
- **A real recipe is always the target, not just a cached category.** If the whole chain
  (plus its speed-budgeted mining) still ends with nothing confirmed and nothing
  unverified, the engine keeps opening the categories it already knows about — one hub at
  a time — until a real recipe link turns up or every known hub has been tried.
- **Stop/rate-limit now imports what was found.** Because `discover()` returns instead of
  throwing, `HarvestModel`'s existing confirmed → unverified → queue fallback chain runs
  normally after a stop or a 429, so autopilot imports whatever was gathered up to that
  point instead of just showing "Browse canceled."
- **Import from a URL, always.** Find & Import has a direct URL field wired to
  `importDirect` — importing a single link no longer requires picking a source or
  category first.
- Files changed vs Build 101: `Harvest/HarvestServices.swift` (`DiscoveryEngine.discover`
  per-engine error/cancellation handling + guaranteed-recipe fallback mining),
  `Harvest/HarvestModel.swift` (`discover()` cancellation-catch message),
  `Views/MacBrowseView.swift` (direct URL import field), `Core/MacBuildConfig.swift`.
- No settings migration (no new persisted keys; revision stays 5).
- Worker impact: none. iOS impact: none.

### Build 101 (4.41) — Autonomy + category catalog — 2026-08-05
- **Autopilot** (default on, `settings.autopilot`, revision 5): one Start runs discover →
  mine + cache categories → import → auto-approve, rotating across the selected sources
  (or the whole catalog) on its own until it runs out or Stop is pressed. Reuses the
  existing rotation + auto-import chain; `startAutopilot(sourceIDs:)` / `stopAutopilot()` /
  `isAutopilotRunning`. Sub-standard recipes still wait in Review. One Stop cancels the
  active discovery/import/verify, clears rotation, keeps everything imported
  (`autopilotStopRequested` guards the mined-import continuation and rotation).
- **Category catalog** (new): every category/hub a run surfaces becomes a first-class,
  browseable `SourceCategory` — named from its slug, organized by taxonomy group, with a
  cached-recipe count. `DiscoveryEngine.discover` now returns `DiscoveryOutcome` (report +
  `[MinedCategory]`); `mineCategories` replaces `expandListings`, opening hubs within the
  speed budget and mining each one's recipes. The model persists a per-source catalog
  (`CategoryCatalog/` dir) and caches each category's recipes (`MinedPageCacheRecord`), so
  drill-in import is instant with no refetch. New model API: `recordCategories`,
  `allCategories`, `readyCategoryCount`, `importCategory`, `importAllReadyCategories`.
- **Categories tab** in Browse: grouped list with per-category "N ready" counts, "Import
  all ready", per-row Import / Mine & Import / Preview, and a source filter.
- **Simplify**: the Find flow leads with an **Autopilot** switch + one adaptive Start/Stop;
  the old Review-first/Automatic picker and multi-variant Start buttons are gone (manual
  controls remain when Autopilot is off). Verify is folded into import as before.
- Files changed vs Build 100: `Harvest/HarvestTypes.swift` (category types, `autopilot`,
  revision 5), `Harvest/RecipeBrowseTaxonomy.swift` (`categoryName`, `group(matchingURL:)`),
  `Harvest/HarvestServices.swift` (`DiscoveryOutcome`, `mineCategories`),
  `Harvest/CrawlCoordinator.swift` (return type), `Harvest/HarvestInfrastructure.swift`
  (`categoryCatalog` path), `Harvest/HarvestModel.swift` (catalog + autopilot),
  `Views/MacBrowseView.swift` (Categories pane + autopilot Start), `Core/MacBuildConfig.swift`.
- Worker impact: none. iOS impact: none.

### Build 100 (4.40) — Harvest + Browse combined; avoid mining — 2026-08-05
- **Harvest folded into Browse.** The separate Harvest sidebar item is gone; Browse is
  now the one place recipes are found, imported AND approved. A segmented switch toggles
  **Find & Import** (the guided flow) and **Review** (the old draft library — search,
  filter, bulk approve/reject on the left, full recipe + Stocked-standards on the right).
  The sidebar's Browse badge shows recipes-to-review first, else queued links. ⌘9 now
  opens Household; Browse stays ⌘B.
- **Guided by default, advanced hidden.** Source, category, workflow, and one Start
  button up front; every power control (crawler method, speed, WebKit, spacing,
  user-agent, python parser, reuse-cache, rotation, source import/export, standards,
  confidence, queue cap, verify/import batch sizes, image + cloud delivery) lives behind
  a single collapsed **Advanced** panel.
- **Avoid mining.** New setting `preferDirectRecipes` (default on): when the direct
  engine (sitemaps/feeds) already yields ≥12 real recipe links, category/listing pages
  are NOT opened and expanded — mining is a fallback, not the norm.
- **Mined recipes go first.** When a category page IS mined (import-time listing refusal
  or bulk-verify), its recipe links are PREPENDED to the queue (new `prependImportURLs`)
  and bulk-verify orders `freshMined + kept + rest`, so mined recipes are verified and
  imported before anything else. In the Automatic workflow they import immediately rather
  than waiting for a press. Convergence rules from Build 98/99 still hold (one generation,
  session-deduped, queue-capped) — the drain strictly shrinks the queue.
- Settings migrated to revision 4 (adds `preferDirectRecipes`; `MinedPageCacheRecord`
  and all Build 98/99 bounds unchanged).
- Files changed vs Build 99: `Harvest/HarvestTypes.swift`, `Harvest/HarvestModel.swift`,
  `Harvest/HarvestServices.swift`, `Views/MacBrowseView.swift` (rebuilt),
  `Views/MacKitchenViews.swift` (MacHarvestView removed; `HarvestDraftDetail` now shared),
  `Views/MacRootView.swift`, `Views/MacCommands.swift`, `Core/MacBuildConfig.swift`.
- Worker impact: none. iOS impact: none.

### Build 99 (4.39) — mining bulk verify + batch dials — 2026-08-02
- Bulk verify replaces category pages with the recipes found on them AND up to five
  sub-pages (bounded 80/hub, session-deduped, queue-capped, WebKit-aware).
- New dials: bulk-verify batch size (25-1000/pass), import batch size (All or
  50-2000/press, button shows "Import first N of M"), alongside the queue cap.
- Import now DRAINS the queue (taken URLs leave the text at run start).
- Worker impact: none. iOS impact: none.

### Build 98 (4.38) — queue control — 2026-08-02
- Mining converges: one generation deep, session-wide mined-set (no URL joins twice),
  mined batches filtered against the library, hard queue cap (default 500, stepper).
- Clean button: removes duplicates / already-imported / failed-this-session with
  counts. Imports skip library-known URLs before spending requests.
- Stop semantics: imported work kept, mined leftovers discarded with a note; a
  stopped browse still delivers its partial report.
- Worker impact: none. iOS impact: none.

### Build 97 (4.37) — resilience — 2026-08-02
- Listicle/roundup slugs classify as listings (suffix/prefix/digit rules, numeric-id
  override); page detector re-judges the RENDERED DOM (hydrated roundups get mined);
  listing detection uses each source's own URL patterns.
- Circuit breaker (8 straight failures/host skips the rest that run, health-visible);
  cancelled ≠ failed; failures dedupe + grouped reason counts + Copy URLs; failed
  links excluded on re-queue; per-run render cache; ephemeral WebKit renderer;
  bulk verify renders blocked pages; activity timestamps.
- Worker impact: none. iOS impact: none.

### Build 96 (4.36) — hub mining + in-pane browser — 2026-08-02
- Failure root cause: category hubs ("breakfast", "dinner") classified as recipes
  under /recipes/. Fixed shape test (hyphen/digit slugs); galleries skipped; hubs
  reaching the importer are MINED — their recipe links auto-join the queue.
- JSON-LD also found in plain <script> hydration payloads (balanced-JSON extractor).
- In-app browser now renders inside the Browse right pane (no sheet): toolbar toggle,
  View on failure rows, Import this page / force-import / Add to queue.
- Failure rows cleaned (slug + site + first verdict); right pane 920pt measure.
- Worker impact: none. iOS impact: none.

### Build 95 (4.35) — importing overhaul — 2026-08-02
- Root cause of mass import failures fixed: truncated UA tripped bot walls; crawler
  now identifies as Safari (one-time migration), with UA presets.
- Parser chain: JSON-LD → microdata → heuristic layout (review-only confidence) →
  Worker; invisible-WebKit rendered-HTML fallback for blocked/JS pages.
- Browsing no longer auto-imports (explicit Import step; migration turns it off once).
- In-app WebKit browser panel (view any https page, Import this page / Add to queue);
  failures panel with reasons + Retry all; import summary card; spacing throttle;
  log de-duplication. Worker impact: none. iOS impact: none.

### Build 94 (4.34) — sitemap fix + Browse redesign — 2026-08-02
- "Stuck on Reading sitemaps" fixed: 20 s request timeouts, breadth-first sitemap walk
  with a per-speed file budget (children of sitemap indexes included), recipe-first
  child prioritization, gzip (.xml.gz) inflation, early stop at the candidate cap.
- Auto method now chains engines (sitemaps → category pages → feeds) until one finds
  recipes; report notes say which engine won.
- Browse UI redesigned: card-based left column (labels above controls — no overlap),
  pause as toolbar button + banner, progress card with bar and live counts, designed
  empty state. Worker impact: none. iOS impact: none.

### Build 93 (4.33) — crawler engines & standards — 2026-08-01
- Crawl method per run (Auto/Sitemaps/Category pages/Feeds) + aggressiveness dial
  (Gentle→Maximum: delays, page budgets, candidate caps; robots/daily limits sacred).
- Category/holiday/birthday hub URLs are opened and mined for recipe links, not queued.
- Communities: 10 reddit cooking subreddits in the catalog (feedOnly); outbound links
  are the candidates, verified at import, attributed to the hosting site.
- Stocked-standards checklist (6 required + 3 recommended) shown per draft and gating
  auto-approval; SourceAttribution guarantees the source shown is the real site or
  author, never "Sowens"/internal handles — notes read "Source: <name> — <url>".
- Worker impact: none. iOS impact: none required (attribution improvement flows
  through household sync automatically).

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
