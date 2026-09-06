# Unified AI, build, and cross-project instructions

This is the single authoritative instruction contract for Codex, Claude, and any other AI or build agent in this repository. Read `README_FIRST.md` first, then read only the sections below that match the current project and task. Legacy instruction filenames link here; do not duplicate rules into them.

## Task routing and updates

1. Identify the current repository and feature boundary before reading or editing code.
2. For UI work, read Product and UI rules; for data/API work, also read Cross-project ownership; for QA tickets, also read QA; for build/release work, also read Validation and publishing.
3. Inspect repository status and preserve unrelated changes. Search for existing implementations and tests before adding another path.
4. Load secrets only from ignored machine-local configuration or Keychain. Never copy values into source, prompts, logs, screenshots, fixtures, or documentation.
5. Default every metered AI request to the lowest-credit supported model and prefer on-device AI when it can satisfy the task. Preserve explicit user/operator model overrides; do not silently promote a default request to a costlier model.
6. When behavior, setup, compatibility, ownership, or validation changes, update the relevant section here and the concise project facts in `README_FIRST.md` in the same verified batch.
7. Shared changes must name an owner, producers, consumers, rollout order, fallback, migration/repair behavior, and verification matrix before publication.
8. Read narrowly to minimize tokens, but never skip a section selected by these routing rules.

## Project and UI rules

Cooklang Federation connections are explicit read-only searches, not background crawlers or generic
RSS import. Keep `CooklangFederation.swift` and `CooklangConnectionPanel.swift` identical to Stocked
iOS. Only validated credential-free HTTPS endpoints may enter preferences. Refuse redirects,
bound streamed responses, cancel replaced work and retain original index text/author provenance.
`MacRecipeInterchangeView(connectedRecipe:)` must stay private: never enable its public-sharing toggle
or bypass the existing duplicate/photo/store gates. A feed curator is not inferred as recipe author.

Recipe archive migration and the folder inbox remain recipe-management features. Maintain the
`KitchenArchive.swift` and `KitchenMigration.swift` copies identically with Stocked iOS; they are
original, deterministic readers of documented formats, not copied Mealie/Tandoor/Paprika code.
Never enable AI fallback, archive execution, unsafe paths, image recompression, or automatic
publication in file ingestion. Preview multiple files within one global 250-recipe / 32-MiB
retained-data budget. Public records still require approved sharing, source attribution and a
validated image. Image-backed personal records may stay household-only under the existing store
contract; missing images remain review blockers on Mac.

`MacRecipeFolderInbox` owns only local bookmark/metadata/hash state. `MacKitchenStore.recipes`
remains the sole approved library. The app-owned watcher must never follow symlinks, scan
subfolders, import/approve/upload records, or claim to run after the app quits. Require stable
observations, bounded hashing, review-time fingerprint validation, and cancellation checks before
updating the queue. Keep pause/remove durable and leave selected-folder files untouched.

Shared ownership: UnifiedWorker owns recipe household/public wire contracts; Stocked iOS and
StockedMac produce and consume additive credit/portable-source metadata. Deploy the Worker’s
old-client omission/privacy preservation before these clients. Missing approval stays private;
top-level private source URLs and legacy Source: notes markers must not reappear. Original-source
fields serve display/export only. Legacy recipes without an envelope retain their previous rules.
Validate shared archive/migration fixtures, native Mac folder/interchange/privacy checks, Worker
compatibility/privacy tests and both app targets before publication. Malformed files remain outside
the library; old backups/household rows still decode and metadata repair is idempotent.

Keep recipe deletion confirmation in both context-menu and keyboard routes; keyboard deletion
requires explicit selection. Catalogue imports must check cancellation after decoding, preserve
case-sensitive URL identities and report rejected records. Worker requests remain HTTPS-only,
redirect-refusing, bounded and cookie-free. See docs/STOCKED_MAC_40_2026_09_05.md for validation.



Every window, page, sheet, popover, and alert must use the StockedMac theme across its complete presentation surface. Layouts and controls must respond to live window size, display scale, accessibility settings, and full-screen or split-window use. Prefer resizable frames, adaptive columns, and minimum sizes; fixed dimensions are only for intentional image/media geometry. Do not lock scrolling where resized windows need it or force scrolling when content fits.

App-level toolbars, sidebars, and tab selectors have one shared implementation and one geometry source. Feature pages must not locally override brand placement, chrome height, safe-area spacing, icon slots, labels, or selected-tab geometry.

## Cross-project ownership and synchronization

Portable recipe file exchange is independently implemented against Cooklang/Schema.org; bounded
local parsing and reviewed source/image validation enter MacKitchenStore only after explicit catalogue
sharing confirmation. Preserve original portableSource privately across household merges, export
author/license/imageAttribution, and never copy raw originals/notes into public harvest. Private iOS
file imports keep their original URL inside portableSource and no public top-level sourceURL until
sharing is approved; respect that on every Mac publication/backfill path. New fields are optional and
legacy clients remain readable. No new pantry/planner/cooking UI or paid service belongs in this batch.
Run native interchange/model/Cooklang checks and StockedMac build; no dependency license is added
for original code. Format/source credits remain visible in Import Center and THIRD_PARTY_NOTICES.md.


- `stocked`: consumes the same image-complete recipe records and household library; its grocery list may consume normalized brand, product, store, and aisle records.
- `UnifiedWorker`: harvest cache, images, recipe/catalog publishing, household sync, and QA.
- `site-repo`: public recipe/content feeds and product information.

Recipe schema, image, provenance, category, deduplication, or sync changes must be applied compatibly across StockedMac, stocked, and UnifiedWorker. Keep older records repairable.

StockedMac owns cuisine discovery collections and their cross-site cache index. Visible cultural categories are limited to Stocked iOS's canonical `RecipeTaxonomy.cuisines` set, excluding the hidden `Other` fallback; more-specific publisher labels remain internal matching evidence. Imported records continue publishing ordinary cuisine/category strings through the existing shared recipe schema, so Stocked iOS and UnifiedWorker require no synthetic collection IDs or migration.

StockedMac also owns the additive schema-1 `recipe-coverage-priority.json` discovery hint. Build it
off-main from approved source-attributed library metadata; export aggregate deficits and terms only.
MacStorageSystem's cache bridge transfers it to server discovery/import ordering. Roll out the
server's tolerant reader before the Mac producer; missing/stale hints retain bounded QA bootstrap
and fair ordinary work. Never use these heuristic discovery counts as iOS result counts, safety
metadata, or permission to bypass the parser/image/provenance gates. Validate native Mac ordering,
server fairness/retry tests and the iOS exact-match/opt-in-alternative selector together.

Category discovery, source indexes, and canonical cuisine matching are background services. Do not
expose a dedicated Categories sidebar destination or navigation shortcut; Browse and automatic
imports consume those caches through the existing validation pipeline.

The expanded English-language global source catalog is StockedMac-owned discovery configuration. Only successfully parsed, image-complete recipes cross into the shared Worker/iOS recipe schema; source profiles and crawling policy do not sync to Stocked iOS.

The Server Mac may prefetch sitemap candidates and deliver versioned immutable batches to StockedMac. It must never write recipes directly to StockedMac, UnifiedWorker, or Stocked iOS. The existing StockedMac import and publication path remains the only funnel into shared recipe data.

StockedMac's Browse screen is the operator view for that bridge. Keep server freshness/source, candidate, pending-batch, acknowledged-batch, approved, and Review counts visible without loading batch contents during SwiftUI rendering. Refresh uses the normal inbox consumer and may never bypass recipe validation. Large inboxes use a materialized pending queue; do not restore per-minute full-directory receipt checks or sorting. The external bridge runs every 30 minutes without rsync compression.

Server category indexes are source-scoped cache hints, not shared recipe taxonomy. Server catalog batches are grocery-only and merge into StockedMac by normalized identity and provenance; they do not bypass the Worker-owned retail adapters or create a second iOS schema.

StockedMac owns incremental recipe batching for household pushes; UnifiedWorker supports additive `responseMode: "ack"` on intermediate batches and returns the legacy full household on the final batch. Older Stocked iOS clients remain compatible and need no request change.
`MacKitchenStore.recipes` is the complete approved Mac recipe database and displayed count whether
or not a household is joined; Harvester, Server inbox, local edits, and household sync all converge
there. Keep large merges indexed by recipe id and periodic signatures allocation-bounded.
Harvester reload and general store saves must never hydrate, classify, compare, or network-fetch the
complete approved library. Historical repairs are separately revisioned, off-main, and batch paced.
The public catalogue is also an independent producer: `MacPublicRecipeSync` must run without
a household and page through the Worker-owned record enumeration until explicit completion.
Automatic passes are bounded and cursor-checkpointed after each accepted page so the durable local
cache grows across launches without loading the complete remote catalogue in one pass. Manual refresh
may use a larger bounded batch. Restore cached recipes and completion metadata before revalidation.
Never infer completion from a short/empty page or a legacy response. Preserve local annotations
and newer edits, and do not echo freshly downloaded catalogue records back through publication.
Merge indexes must tolerate historical duplicate UUIDs without crashing. Failed image validation
does not make a source-attributed import personal and must never trigger public deletion.

Brand/store discovery is grocery-scoped and uses Open Food Facts, USDA FoodData Central, OpenStreetMap, Wikidata/Wikimedia Commons, Stocked's offline grocery-brand/store reference, and the offline aisle taxonomy. Do not add dedicated beauty, pet, or general-merchandise catalogs. Catalog records may carry optional `imageURL`, `imagePreviewURL`, `imageSourceURL`, and `imageAttribution`; old saved records without them must continue decoding. Preserve original-resolution URLs and attribution, use previews only for rendering, fault-isolate providers, and enrich duplicates in both durable queues and the imported library.

Official Kroger and allowlisted RapidAPI requests are owned by UnifiedWorker `/retail/*` routes. StockedMac owns discovery/import tooling; Stocked iOS consumes normalized store/product metadata. Keep provider/store IDs optional for backward compatibility, keep live price/availability short-lived, and never persist provider secrets in either app.

H-E-B live reads from `texas-grocery-mcp` remain a local/Server-Mac enrichment option until a
private authenticated gateway is explicitly implemented. Do not put H-E-B cookies, credentials,
cart actions, or the unofficial GraphQL session in StockedMac, Stocked iOS, GitHub, or public Worker
configuration. Texas-specific app enrichment must retain the official/open-source fallback chain.

## Shared safety, validation, and publishing contract


### Project intake

1. Begin with the named entry point and expand scope only when evidence requires it.
2. State the feature boundary before editing so adjacent shipped behavior is preserved.
3. Identify the authoritative local, server, and generated data sources before changing models.
4. Keep credentials, signing material, user data, and machine-local configuration outside commits.
5. Treat released schemas, URLs, deep links, persistence formats, and extension contracts as compatibility surfaces.
6. Preserve offline/local-first behavior and provide a recoverable failure path for optional services.
7. Apply the complete product theme, adaptive layout, Dynamic Type, accessibility, and device-size contract to UI work.
8. Prefer migrations and retroactive repair over destructive replacement of existing records.
9. Run the narrowest meaningful validation first, then every affected target or consumer.
10. Finish only when behavior, setup, verification, documentation, and cross-project impact agree.

### Implementation and verification

1. Inspect repository status first and preserve unrelated user or agent work.
2. Make the smallest coherent batch that resolves the root cause without silently dropping features.
3. Search for existing abstractions, tests, and generated sources before adding parallel implementations.
4. Never expose secrets in code, logs, screenshots, fixtures, commits, or implementation briefs.
5. Keep public and persisted changes additive unless an explicit, tested migration removes the old path.
6. Update all affected app, widget, extension, Worker, site, and tooling consumers in the same coordinated task.
7. Test empty, loading, failure, offline, cancellation, retry, duplicate, and accessibility states when relevant.
8. Do not publish, deploy, migrate production data, or mark QA resolved after failed validation.
9. Record material decisions and new invariants in the existing short guides without duplicating large documentation.
10. Hand off with changed files, validation evidence, deferred risks, and any required operator action.

### Cross-project delivery

1. Name one owning repository for every shared schema, route, asset, or generated artifact.
2. List every producer and consumer before modifying a shared contract.
3. Preserve older clients with additive fields, tolerant decoding, stable URLs, and routing shims where required.
4. Define rollout order so providers remain compatible before consumers adopt new behavior.
5. Make migrations idempotent, resumable, observable, and safe to retry after interruption.
6. Keep secrets server-side or machine-local and synchronize only names, requirements, and validation—not values.
7. Propagate fixes retroactively to stored records when the invariant applies to old and new data.
8. Validate a matrix covering the owner, direct consumers, extensions/widgets, public content, and fallback paths.
9. Update README-first, AI instructions, cross-project sync, and public documentation in the same verified batch.
10. Retain a rollback or compatibility path until deployed clients and persisted data confirm the new contract.
