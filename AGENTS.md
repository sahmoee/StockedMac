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



Every window, page, sheet, popover, and alert must use the StockedMac theme across its complete presentation surface. Layouts and controls must respond to live window size, display scale, accessibility settings, and full-screen or split-window use. Prefer resizable frames, adaptive columns, and minimum sizes; fixed dimensions are only for intentional image/media geometry. Do not lock scrolling where resized windows need it or force scrolling when content fits.

App-level toolbars, sidebars, and tab selectors have one shared implementation and one geometry source. Feature pages must not locally override brand placement, chrome height, safe-area spacing, icon slots, labels, or selected-tab geometry.

## Cross-project ownership and synchronization


- `stocked`: consumes the same image-complete recipe records and household library; its grocery list may consume normalized brand, product, store, and aisle records.
- `UnifiedWorker`: harvest cache, images, recipe/catalog publishing, household sync, and QA.
- `site-repo`: public recipe/content feeds and product information.

Recipe schema, image, provenance, category, deduplication, or sync changes must be applied compatibly across StockedMac, stocked, and UnifiedWorker. Keep older records repairable.

StockedMac owns cuisine discovery collections and their cross-site cache index. Visible cultural categories are limited to Stocked iOS's canonical `RecipeTaxonomy.cuisines` set, excluding the hidden `Other` fallback; more-specific publisher labels remain internal matching evidence. Imported records continue publishing ordinary cuisine/category strings through the existing shared recipe schema, so Stocked iOS and UnifiedWorker require no synthetic collection IDs or migration.

The expanded English-language global source catalog is StockedMac-owned discovery configuration. Only successfully parsed, image-complete recipes cross into the shared Worker/iOS recipe schema; source profiles and crawling policy do not sync to Stocked iOS.

The Server Mac may prefetch sitemap candidates and deliver versioned immutable batches to StockedMac. It must never write recipes directly to StockedMac, UnifiedWorker, or Stocked iOS. The existing StockedMac import and publication path remains the only funnel into shared recipe data.

StockedMac's Browse screen is the operator view for that bridge. Keep server freshness/source, candidate, pending-batch, acknowledged-batch, approved, and Review counts visible without loading batch contents during SwiftUI rendering. Refresh uses the normal inbox consumer and may never bypass recipe validation.

Server category indexes are source-scoped cache hints, not shared recipe taxonomy. Server catalog batches are grocery-only and merge into StockedMac by normalized identity and provenance; they do not bypass the Worker-owned retail adapters or create a second iOS schema.

StockedMac owns incremental recipe batching for household pushes; UnifiedWorker supports additive `responseMode: "ack"` on intermediate batches and returns the legacy full household on the final batch. Older Stocked iOS clients remain compatible and need no request change.

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
