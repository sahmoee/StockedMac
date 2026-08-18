# Cross-project sync

Also apply the ten additive cross-project safeguards in `PROJECT_GUIDE_ADDITIONS.md`; existing ownership and compatibility rules remain authoritative.

- `stocked`: consumes the same image-complete recipe records and household library; its grocery list may consume normalized brand, product, store, and aisle records.
- `UnifiedWorker`: harvest cache, images, recipe/catalog publishing, household sync, and QA.
- `site-repo`: public recipe/content feeds and product information.

Recipe schema, image, provenance, category, deduplication, or sync changes must be applied compatibly across StockedMac, stocked, and UnifiedWorker. Keep older records repairable.

StockedMac owns cuisine discovery collections and their cross-site cache index. Imported records continue publishing ordinary cuisine/category strings through the existing shared recipe schema, so Stocked iOS and UnifiedWorker require no synthetic collection IDs or migration.

The expanded English-language global source catalog is StockedMac-owned discovery configuration. Only successfully parsed, image-complete recipes cross into the shared Worker/iOS recipe schema; source profiles and crawling policy do not sync to Stocked iOS.

StockedMac owns incremental recipe batching for household pushes; UnifiedWorker supports additive `responseMode: "ack"` on intermediate batches and returns the legacy full household on the final batch. Older Stocked iOS clients remain compatible and need no request change.

Brand/store discovery is grocery-scoped and uses Open Food Facts, USDA FoodData Central, OpenStreetMap, Wikidata/Wikimedia Commons, Stocked's offline grocery-brand/store reference, and the offline aisle taxonomy. Do not add dedicated beauty, pet, or general-merchandise catalogs. Catalog records may carry optional `imageURL`, `imagePreviewURL`, `imageSourceURL`, and `imageAttribution`; old saved records without them must continue decoding. Preserve original-resolution URLs and attribution, use previews only for rendering, fault-isolate providers, and enrich duplicates in both durable queues and the imported library.

Official Kroger and allowlisted RapidAPI requests are owned by UnifiedWorker `/retail/*` routes. StockedMac owns discovery/import tooling; Stocked iOS consumes normalized store/product metadata. Keep provider/store IDs optional for backward compatibility, keep live price/availability short-lived, and never persist provider secrets in either app.

H-E-B live reads from `texas-grocery-mcp` remain a local/Server-Mac enrichment option until a
private authenticated gateway is explicitly implemented. Do not put H-E-B cookies, credentials,
cart actions, or the unofficial GraphQL session in StockedMac, Stocked iOS, GitHub, or public Worker
configuration. Texas-specific app enrichment must retain the official/open-source fallback chain.
