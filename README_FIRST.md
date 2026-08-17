# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

StockedMac is the content-management companion to Stocked iOS. It imports, repairs, edits, categorizes, images, and publishes recipes, and maintains the shared brands, products, stores, and grocery-aisle catalog. Do not restore inventory, grocery-list, meal-planning, cooking, or analytics workflows. Imported recipes require a usable image and original source attribution. Catalog records require source provenance and must remain deduplicated and resumable.

Brand/store discovery is grocery-scoped, additive, and fault-isolated. Preserve the offline grocery reference catalog, Open Food Facts, USDA, OpenStreetMap, and Wikidata/Commons support; do not add dedicated beauty, pet, or general-merchandise catalogs. Keep original image URLs plus attribution, use preview URLs only for display performance, and merge new metadata into matching queued or imported records rather than duplicating or overwriting stronger data.

Kroger discovery uses the authenticated UnifiedWorker retail gateway; Kroger and RapidAPI credentials remain server-side. Preserve official store IDs, UPCs, current price/availability, exact aisle/shelf data, provenance, and the largest original product image. RapidAPI data is fallback-only. For bulk repair or import cleanup, run `scripts/catalog-quality.py`; keep it deterministic, standard-library-only, and safe to rerun.

`Secrets.xcconfig` is local and ignored. Production sync uses `https://api.sowensstudios.com`. Preserve partial scan results, resumable queues, limits, deduplication, and retroactive repair. Verify the `StockedMac` scheme.

The normal Find flow is hands-off: discovery imports immediately, complete image-backed recipes approve and publish automatically, and only incomplete records wait for attention. Preserve original image bytes and URLs; never introduce lossy sync re-encoding.
