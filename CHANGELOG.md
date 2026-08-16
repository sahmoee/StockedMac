# Changelog

- Added two recipe intake methods: bulk link-file import for browser bookmark HTML, `.webloc`, `.url`, CSV, and text exports; and QR-code image import for recipe links from screenshots, cards, books, or packaging. Both reuse finite batches, the durable queue, verification, deduplication, and mandatory image enforcement.
- Upgraded the in-app WebKit browser with default-on live recipe capture. Every completed navigation is classified in the background: recipe pages enter the durable queue automatically, category/listing pages contribute their discovered recipe links, duplicates are skipped, and browsing is never interrupted by classifier failures.
- Made usable downloaded images a permanent ingestion invariant across direct, category, queued, automatic, retry, refresh, and bulk imports. Every library reload continuously removes older image-less Harvester imports and image-less source-backed shared recipes, and publishes their deletions through household sync.
- Recipe categories now travel into every newly imported recipe using structured metadata plus conservative title/source taxonomy inference. Historical repair v3 backfills the same categories into previously imported Mac drafts and the shared Stocked iOS library, without importing category or roundup pages as recipes.

Every push should add an entry here so GitHub carries the build/change history.
Newest at the top. Keep it plain ASCII (see .gitmessage.txt for the commit rules).

## Build 113 — One-step intake and original images

- Discovery now defaults to immediate import, automatic approval for complete image-backed recipes, and shared-library sync without intermediate queue or review clicks.
- Existing preference files migrate to the simplified flow while incomplete recipes remain safely visible for attention.
- Stopped lossy image re-encoding; oversized originals travel by their source URL, and historical recipes enter repair v2 for refresh and republishing.

## Build 112 — Priority-ranked recipe sources

- Added 40 structured-recipe sources after checking robots and sitemap availability, bringing the built-in catalog to 150.
- Ranked sources with locally proven successful imports first, currently discovery-friendly sites next, and access-limited/community feeds last.
- Existing installs now receive new built-ins and priority changes without losing local enabled flags, learned health, or custom sources.
- Added a reproducible catalog updater that keeps both JSON copies and the compiled Swift fallback identical.

## Build 111 — Retroactive repairs and required images

- Added a versioned historical repair framework that normalizes old Harvester and shared recipes, then reparses every previous source through a durable, finite, resumable backlog.
- Restored images as a hard requirement for approval, Mac handoff, Worker publication, and household sync; recovered images update existing shared recipes instead of being skipped as duplicates.
- Added historical repair status, adjustable batch size, and manual resume controls to Recipe Sync.

## Build 110 — Higher-throughput recipe intake

- Implemented twenty import improvements covering optional images, simpler approval, larger adjustable finite batches, five-source browsing, multi-engine accumulation, stronger URL normalization, content-based duplicate merging, and richer categories.
- Preserved resumable queues, partial-result caching, rate-limit deferral, source attribution, and finite stopping rules while increasing the number of useful recipes that reach Stocked iOS.

## Build 109 — Recipe Manager

- Converted the visible Mac app into a dedicated recipe manager: Recipes, Find & Import, Categories, and Recipe Sync.
- Added source publisher, source URL, and recipe categories to the shared Mac/iOS recipe model and cloud payloads; imported recipes no longer attribute their source to StockedMac.
- Added adjustable scan and import limits, a durable queue, cancellation recovery, cached partial mining results, category-page queue expansion, rate-limit deferral, and finite source rotation.
- Disabled non-recipe household collections on Mac while preserving recipe collaboration with Stocked iOS.

## Build 108 — Version 4.43

- The complete Recipes library now backfills to the shared iPhone and iPad catalog on launch, including recipes created before automatic Harvester publishing existed.
- Full-catalog uploads remain safe to repeat because recipes are updated by stable UUID.

## Build 107 — Version 4.43

- Approved Stocked Mac recipes now publish automatically to the shared Stocked recipe database used by every app install.
- Harvest payloads identify Stocked Mac as the importer and carry a stable import timestamp for household activity.

## Build 106 — Version 4.43

- Recognizes access challenges before counting recipe links, preventing bot-wall JavaScript from being mislabeled and recursively queued as category pages.
- Excludes favicons, vector images, fonts, and additional media extensions from discovery before they can generate page-decode failures.
- Skips the local Python attempt when that optional helper is unavailable in the app sandbox, keeping import errors focused on parsers that actually ran.

## Build 105 — Version 4.43

- Fixed valid JSON-LD recipe pages being mistaken for category pages when they also linked to related recipes.
- Added a searchable category filter for occasions, drinks, holidays, cuisines, diets, methods, and seasons.
- Found recipes from multiple websites now accumulate in one explicit import queue before processing.
- Access-limited, paywalled, robots-blocked, and rate-limited sources leave automatic discovery while direct import remains available.
- Hardened the native fetch headers, bundled Python JSON-LD/recipe-card fallbacks, and gzip-aware batch harvesting script.

## Build 104 — Version 4.43

- Build 104 keeps version 4.43 and redesigns recipe import around a three-step guided flow.
- Added direct one-recipe URL import, pasted recipe parsing, and screenshot text recognition.
- Made website discovery optional, limited each pass to three sources, capped visible results to a focused batch, and removed the extra queue step for selected recipes.
- Added review search, sorting, attention filters, readiness checks, and explicit Approve & Send delivery into the Mac kitchen and Stocked iOS harvest sync.
- Normalized more tracking parameters before importing recipe URLs.
