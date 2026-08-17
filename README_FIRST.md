# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

StockedMac is the content-management companion to Stocked iOS. It imports, repairs, edits, categorizes, images, and publishes recipes, and maintains the shared brands, products, stores, and grocery-aisle catalog. Do not restore inventory, grocery-list, meal-planning, cooking, or analytics workflows. Imported recipes require a usable image and original source attribution. Catalog records require source provenance and must remain deduplicated and resumable.

Brand/store discovery is additive and fault-isolated. Preserve the offline reference catalog, Open Facts family providers, USDA, OpenStreetMap, and Wikidata/Commons support. Keep original image URLs plus attribution, use preview URLs only for display performance, and merge new metadata into matching queued or imported records rather than duplicating or overwriting stronger data.

`Secrets.xcconfig` is local and ignored. Production sync uses `https://api.sowensstudios.com`. Preserve partial scan results, resumable queues, limits, deduplication, and retroactive repair. Verify the `StockedMac` scheme.

The normal Find flow is hands-off: discovery imports immediately, complete image-backed recipes approve and publish automatically, and only incomplete records wait for attention. Preserve original image bytes and URLs; never introduce lossy sync re-encoding.
