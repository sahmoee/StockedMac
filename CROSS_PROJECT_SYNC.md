# Cross-project sync

Also apply the ten additive cross-project safeguards in `PROJECT_GUIDE_ADDITIONS.md`; existing ownership and compatibility rules remain authoritative.

- `stocked`: consumes the same image-complete recipe records and household library; its grocery list may consume normalized brand, product, store, and aisle records.
- `UnifiedWorker`: harvest cache, images, recipe/catalog publishing, household sync, and QA.
- `site-repo`: public recipe/content feeds and product information.

Recipe schema, image, provenance, category, deduplication, or sync changes must be applied compatibly across StockedMac, stocked, and UnifiedWorker. Keep older records repairable.

Brand/store discovery is grocery-scoped and uses Open Food Facts, USDA FoodData Central, OpenStreetMap, Wikidata/Wikimedia Commons, Stocked's offline grocery-brand/store reference, and the offline aisle taxonomy. Do not add dedicated beauty, pet, or general-merchandise catalogs. Catalog records may carry optional `imageURL`, `imagePreviewURL`, `imageSourceURL`, and `imageAttribution`; old saved records without them must continue decoding. Preserve original-resolution URLs and attribution, use previews only for rendering, fault-isolate providers, and enrich duplicates in both durable queues and the imported library.
