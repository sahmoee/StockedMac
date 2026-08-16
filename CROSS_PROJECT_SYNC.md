# Cross-project sync

- `stocked`: consumes the same image-complete recipe records and household library.
- `UnifiedWorker`: harvest cache, images, catalog publishing, household sync, and QA.
- `site-repo`: public recipe/content feeds and product information.

Recipe schema, image, provenance, category, deduplication, or sync changes must be applied compatibly across StockedMac, stocked, and UnifiedWorker. Keep older records repairable.
