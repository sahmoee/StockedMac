# Cross-project sync

- `stocked`: consumes the same image-complete recipe records and household library; its grocery list may consume normalized brand, product, store, and aisle records.
- `UnifiedWorker`: harvest cache, images, recipe/catalog publishing, household sync, and QA.
- `site-repo`: public recipe/content feeds and product information.

Recipe schema, image, provenance, category, deduplication, or sync changes must be applied compatibly across StockedMac, stocked, and UnifiedWorker. Keep older records repairable.

Brand/store discovery uses Open Food Facts, USDA FoodData Central, OpenStreetMap, and Stocked's offline aisle taxonomy. Preserve source URLs, API attribution, durable queues, deduplication keys, and optional-key behavior when extending it.
