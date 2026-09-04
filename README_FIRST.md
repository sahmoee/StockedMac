# Read me first

StockedMac pulls the public catalogue at launch and every 15 minutes, independently of
household membership. Recipes offers a refresh control, explicit completeness status, and
filtered-versus-total local counts. The Worker-owned `harvest/recipes?pageSize=100&cursor=...`
contract enumerates actual stored records, including imports outside the legacy capped index.
Pages merge into the existing library by UUID/canonical source; local notes, favourites, and
newer edits survive. Catalogue image URLs load on demand, not in a whole-library image pass.
Deploy the additive Worker route before shipping this Mac client. Legacy responses still load
but show a server-update warning rather than claiming a complete catalogue. Failures preserve
previously loaded records, and subsequent passes safely replay pages. iOS's legacy route is unchanged.
The standalone `scripts/test-public-catalogue.swift` harness validates production decoding,
stable identities, image URL resolution, private-row exclusion, empty-page continuation,
legacy warnings, and repeated-cursor failure using fake transport/store boundaries.

Household merge indexes tolerate legacy duplicate UUIDs without trapping. Public cleanup must
distinguish source-less recipes from imports awaiting image repair; a failed image gate alone
does not authorize deletion from the shared catalogue.

StockedMac is the content-management companion to Stocked iOS. It imports, repairs, edits, categorizes, images, and publishes recipes, and maintains the shared brands, products, stores, and grocery-aisle catalog. Do not restore inventory, grocery-list, meal-planning, cooking, or analytics workflows. Imported recipes require a usable image and original source attribution. Catalog records require source provenance and must remain deduplicated and resumable.

Shared household cooking is owned by Stocked iOS and UnifiedWorker. StockedMac remains a tolerant
household client and recipe producer; it does not display or author `activeCookSessions`.

The Mac desktop shell is a native recipe-management workspace. Its shared `MacDesktopExperience`
owns persisted list/table presentation, comfortable/compact density, inspector visibility, the
Command Palette, and Import Center. Recipes can open in independent windows and Quick Look;
the menu-bar extra reports recipe pipeline state rather than exposing the retired kitchen UI.
Keep the four visible sidebar shortcuts unique (`⌘1` through `⌘4`), keep import/export under File,
and route URL or file drops through the existing validation, merge, tombstone, and publication
paths. Presentation preferences may never mutate recipe data or cap macOS accessibility text.

Brand/store discovery is grocery-scoped, additive, and fault-isolated. Preserve the offline grocery reference catalog, Open Food Facts, USDA, OpenStreetMap, and Wikidata/Commons support; do not add dedicated beauty, pet, or general-merchandise catalogs. Keep original image URLs plus attribution, use preview URLs only for display performance, and merge new metadata into matching queued or imported records rather than duplicating or overwriting stronger data.

Kroger discovery uses the authenticated UnifiedWorker retail gateway; Kroger and RapidAPI credentials remain server-side. Preserve official store IDs, UPCs, current price/availability, exact aisle/shelf data, provenance, and the largest original product image. RapidAPI data is fallback-only. For bulk repair or import cleanup, run `scripts/catalog-quality.py`; keep it deterministic, standard-library-only, and safe to rerun.

`Secrets.xcconfig` is local and ignored. Production sync uses `https://api.sowensstudios.com`. Preserve partial scan results, resumable queues, limits, deduplication, and retroactive repair. Verify the `StockedMac` scheme.

`macThemedSurface()` owns the adaptive warm canvas for every scene and presentation; `MacCard` uses the matching semantic card and border colors. Apply these shared primitives to new windows, sheets, popovers, and detached panels instead of native window backgrounds or fixed light/dark colors.

The normal Find flow is hands-off: discovery imports immediately, complete image-backed recipes approve and publish automatically, and only incomplete records wait for attention. Preserve original image bytes and URLs; never introduce lossy sync re-encoding.
Imported recipes are shared catalogue records regardless of household membership. Always retain
their original publisher attribution and source URL; rights remain with that source. Only genuinely
personal source-less recipes may remain household-scoped.
The launch backfill republishes all historical source-attributed imports and removes source-less
recipe UUIDs that an older release may have placed in the public index; both operations are safe to
retry.

Recipe scan and import batches accept typed limits from 1 through 2,000. Multi-source runs may randomize the selected source subset and candidate order for variety, but randomization changes order only: requests remain bounded, serial per host, resumable, cooldown-aware, deduplicated, and subject to the same image and attribution gates.

Category discovery and canonical cross-site cuisine collections run in the background and feed the
ordinary Browse/import pipeline. Do not expose a dedicated Categories destination in the sidebar,
command palette, or section shortcuts; do not compute the category index during SwiftUI rendering.

STK-89-0135: Jamaican is a canonical collection aligned with iOS. `RecipeCoveragePlan` measures
underfilled discovery categories from the approved, source-attributed Mac library off the main actor.
It emits `recipe-coverage-priority.json` (schema 1, aggregate deficits/terms only) through the existing
cache bridge to Stocked Server. Automatic source selection now samples the complete source pool
before limiting, and source/candidate ordering alternates gap-priority and ordinary work. The initial
Jamaican/chicken QA hint expires when measured coverage reaches 12; this is not a promise of 12
matches for every quiz combination. No eligibility, dietary or Comfort labels are inferred by this plan.
Native check: compile `RecipeBrowseTaxonomy.swift`, `RecipeCoveragePlan.swift`, and
`scripts/test-recipe-coverage.swift`; then build the `StockedMac` target normally.

The visible `Cuisines & cultures` collection must match Stocked iOS `RecipeTaxonomy.cuisines`, except that the non-browsable `Other` fallback stays hidden. Normalize specific publisher labels into that shared set; never expand the Mac-only cultural taxonomy independently.

Category rows stay materialized, and the cross-site cuisine cache rebuilds off the main actor with coalescing. Never restore per-render catalog sorting, per-cuisine repeated normalization, or synchronous reads of every cached report/category file; those paths block sidebar tab selection on large libraries.

Stocked Server is an independent discovery and preverification tier. It discovers into a durable server-owned queue, invokes the same bundled structured-recipe parser headlessly, requires usable image bytes plus complete ingredients and instructions, and deduplicates by canonical URL without requiring StockedMac to be open. Transient failures retry with bounded exponential backoff; terminal or incomplete records enter the server review outbox. Preverified URLs are still untrusted candidates: StockedMac remains the only final parser, approval, Worker-publication, and household/iOS-sync boundary.

The Browse screen must keep Stocked Server observable at launch: show service freshness/current source, discovery candidates, server queue/retry/verified/review counts, and local review. The five-minute bridge transfers immutable preverified candidates into `ServerInbox`; the one-minute app consumer re-runs the ordinary local gates and drains the durable queue in finite passes. Manual refresh invokes that same safe consumer.

Stocked Server discovery runs every 15 minutes and its separately locked importer drains work every five minutes. Discovery uses a persisted no-repeat shuffle bag, per-source deadlines, source cooldowns, a whole-run budget, media-URL filtering, and durable-queue backpressure. The architecture-neutral parser is launch-probed before queue work and past architecture failures are requeued automatically. It may randomize fair work order, but must never bypass robots, authentication, throttling, the required-image gate, canonical source attribution, or complete-recipe validation. Imported and historical titles are standardized only when their casing is clearly broken; intentional publisher casing remains intact.

Server batches may also carry source-scoped category indexes and grocery catalog records. Category indexes populate the same mined-page cache; grocery records enter only through `CatalogModel`'s grocery-only provenance and identity merge. Health telemetry is display-only and can never bypass a gate or make server availability a launch dependency.

WebKit is a bounded fallback and interactive browser, not a background crawler. Reuse the single hidden renderer, block its image/media/font resources, replace extracted documents with inert content, and fully dismantle visible browser delegates and observers when their view closes. Never add private sandbox entitlements to suppress WebContent diagnostics.

The built-in recipe catalog contains 250 sources, including an audited batch of 100 English-language global publishers. Keep `default-sources.json` and `DefaultSourceCatalog.swift` synchronized. New sources require a reachable HTTPS homepage and XML sitemap, remain robots-aware and serial per host, and must not weaken the normal image, attribution, duplicate, or rate-limit gates.

Household recipe sync is incremental and lossless: changed image-backed recipes are packed into complete byte-bounded pushes, intermediate batches request Worker acknowledgements, and only the final batch downloads and applies the merged household. Never restore tail trimming or full-library encoding every 30 seconds.
The Recipes library is the Mac's complete approved recipe database whether or not the Mac has
joined a household. Harvester approval and Server-inbox consumption both enter that same
`MacKitchenStore.recipes` collection; household sync is an additional producer/consumer, not a
filter on the library or its displayed total. Large household merges must use maintained id
indexes, and periodic sync fingerprints must not assemble a duplicate full-library payload.
The fourth sidebar destination is `Household Sync`. When the Mac is not joined, the sidebar footer also exposes `Enter household code`; both routes open the full join/create household screen rather than a separate abbreviated sync form.
Recoverable household storage failures retry automatically with capped 0.5, 1, and 2 second
backoff while the UI reports `Repairing household storage…`; exhausted repair remains eligible for
the ordinary 30-second auto-sync instead of becoming a permanent local pause.

Every recipe-repair revision applies the latest nutrition, category, source, and image extraction to historical source URLs in bounded resumable batches; future imports use the same path. FatSecret enrichment is additive and may never replace stronger publisher/USDA facts or invent store-specific aisle, price, or inventory data.

The Brands & Stores catalog continuously reprocesses existing and future records through every
applicable enabled grocery source using persisted rotating cursors. Inventory additions and edits
also enqueue catalog enrichment immediately, including edits produced by AI workflows. Sources
merge only matching names or barcodes, preserve original provenance, keep partial improvements,
and cannot trap the queue on a failed provider.
Catalog batch merges must use maintained identity indexes rather than repeated full-library scans.
Persist large catalog snapshots off the main actor, coalesce rapid changes, and keep displayed
thumbnails in a bounded decoded-image cache so discovery never blocks tab selection or scrolling.
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
