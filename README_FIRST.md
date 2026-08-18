# Read me first

Also apply the ten additive README-first safeguards in `PROJECT_GUIDE_ADDITIONS.md`; they extend this project-specific contract without removing existing functionality.

StockedMac is the content-management companion to Stocked iOS. It imports, repairs, edits, categorizes, images, and publishes recipes, and maintains the shared brands, products, stores, and grocery-aisle catalog. Do not restore inventory, grocery-list, meal-planning, cooking, or analytics workflows. Imported recipes require a usable image and original source attribution. Catalog records require source provenance and must remain deduplicated and resumable.

Brand/store discovery is grocery-scoped, additive, and fault-isolated. Preserve the offline grocery reference catalog, Open Food Facts, USDA, OpenStreetMap, and Wikidata/Commons support; do not add dedicated beauty, pet, or general-merchandise catalogs. Keep original image URLs plus attribution, use preview URLs only for display performance, and merge new metadata into matching queued or imported records rather than duplicating or overwriting stronger data.

Kroger discovery uses the authenticated UnifiedWorker retail gateway; Kroger and RapidAPI credentials remain server-side. Preserve official store IDs, UPCs, current price/availability, exact aisle/shelf data, provenance, and the largest original product image. RapidAPI data is fallback-only. For bulk repair or import cleanup, run `scripts/catalog-quality.py`; keep it deterministic, standard-library-only, and safe to rerun.

`Secrets.xcconfig` is local and ignored. Production sync uses `https://api.sowensstudios.com`. Preserve partial scan results, resumable queues, limits, deduplication, and retroactive repair. Verify the `StockedMac` scheme.

The normal Find flow is hands-off: discovery imports immediately, complete image-backed recipes approve and publish automatically, and only incomplete records wait for attention. Preserve original image bytes and URLs; never introduce lossy sync re-encoding.

Every recipe-repair revision applies the latest nutrition, category, source, and image extraction to historical source URLs in bounded resumable batches; future imports use the same path. FatSecret enrichment is additive and may never replace stronger publisher/USDA facts or invent store-specific aisle, price, or inventory data.

The Brands & Stores catalog continuously reprocesses existing and future records through every
applicable enabled grocery source using persisted rotating cursors. Inventory additions and edits
also enqueue catalog enrichment immediately, including edits produced by AI workflows. Sources
merge only matching names or barcodes, preserve original provenance, keep partial improvements,
and cannot trap the queue on a failed provider.

Automatic bulk catalog import is enabled by default. It rotates through the built-in grocery
taxonomy, store regions, every enabled source, and provider result pages; imports partial results
immediately; and persists source, term, region, page, and cooldown state across relaunches. No item,
brand, or store name needs to be typed. A 429 or provider failure cools only that provider while the
rest of the sweep advances. Never replace this with concurrent unbounded requests or quota-evasion.
Kroger, RapidAPI, and FatSecret remain Worker-mediated; FatSecret may use Server Mac fixed egress.

Texas ZIPs and Texas region text prioritize H-E-B enrichment: Stocked's verified H-E-B reference,
H-E-B-specific OpenStreetMap discovery, then H-E-B-targeted Open Food Facts, USDA, FatSecret, and
Wikimedia lookups. The optional `texas-grocery-mcp` installed for local AI chats is unofficial,
session-dependent, and read-oriented; keep its browser state outside the app, throttle it, and never
make StockedMac depend on it for startup or discard existing data when it is unavailable.

AI is Apple-first when Foundation Models are available. Included cloud AI is only unlocked on Jessie's production/test devices with the local `Joo` gate; other installs use a private UnifiedWorker. Private Workers may select Claude or OpenAI model IDs and keep provider keys in Worker secrets, never in the app.
