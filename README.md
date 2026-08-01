# Build 93 (4.33) — crawler engines, aggressiveness, communities, and standards

**Mac delta only.** No worker or iOS change — the Build 91 worker deploy still covers
everything. The full `StockedMac/` folder is included (Builds 91+92 files with 93 on top),
so this one package over your tree lands you correct regardless of what was copied before.

---

## Crawl methods and aggressiveness

Two new controls in Browse ▸ Sources:

**Method** — how a run hunts for candidates:

| Method | What it does |
|---|---|
| Auto (per source) | Each source uses the engine it's configured for (default) |
| Sitemaps | Reads sitemap.xml files (the old engine, now budgeted) |
| Category pages | Crawls listing/category pages and follows the recipe links printed on them — for sites with useless sitemaps |
| Feeds | Reads RSS/Atom feeds, including reddit |

**Speed** — Gentle / Balanced / Aggressive / Maximum. One dial scales request spacing
(2× down to 0.25× each site's own delay), sitemap/feed/page budgets (3→24 seeds),
category-page expansion (4→40 pages) and the per-run candidate cap (150→2,500).
Robots.txt and per-source daily limits are never overridden, and a 0.5 s politeness
floor always applies. The run's report says what got skipped or capped and why.

## Actual recipes, not "Birthdays"

Sitemap URLs are now classified before anything is queued. Recipe-shaped URLs go straight
to the candidate list. Listing-shaped URLs — `/category/…`, `/holiday…`, `/birthday…`,
`/collection…`, roundups, pagination, bare `/recipes/` indexes — are **opened and mined
for the recipe links they contain** (up to the speed budget) instead of being imported as
if they were dinner. The importer's page detector remains the final judge, so any hub that
slips through is refused at import, not saved.

## Communities — reddit and beyond

Ten reddit cooking communities ship in the catalog under a new **Communities & feeds**
group in the source picker: r/recipes, r/Cooking, r/food, r/slowcooking, r/MealPrepSunday,
r/EatCheapAndHealthy, r/Baking, r/veganrecipes, r/ketorecipes, r/Old_Recipes. They browse
via their `.rss` feeds; for these aggregators the **outbound link in each post** is the
candidate (media hosts like imgur/youtube are dropped), and every link faces the full
recipe verification at import. Recipes found through reddit are attributed to the site
that actually hosts them, not to reddit.

Any similar community or blog feed can be added the same way — via the file import
(Build 92) or a custom source with discovery mode "Feed (RSS/Atom/reddit)".

## Stocked standards

Every draft's detail view now shows a **Stocked standards** card: six required checks
(titled like a recipe, ≥3 ingredients, ≥2 method steps, image saved to disk, real source
URL, honest attribution) and three recommended ones (servings, a time, a description),
each with a pass/fail mark and a reason. A failing draft says plainly that it won't
auto-approve.

Auto-approval now requires, on top of the confidence threshold: no warnings, no
duplicates, the image on disk, **and all required standards passing** ("Only auto-approve
recipes that meet Stocked standards", on by default, in Browse ▸ Verification).

## Attribution — never "Sowens"

One authority (`SourceAttribution`) now decides what "Source:" says everywhere: the
site's real catalog name → the recipe's author → the plain host, in that order. Internal
and generic handles ("Sowens", "Stocked Companion", "custom-…", "imported-…", "unknown")
never qualify. The crawler stamps it on every draft, the kitchen bridge writes it into
the recipe's notes as `Source: <name> — <url>`, and the cloud cache uploads carry the
same field — so what the phone shows is the real origin, with the link beside it.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/` (folder structure kept).
2. Build Settings: `MARKETING_VERSION = 4.33`, `CURRENT_PROJECT_VERSION = 93`.
3. Launch — the ten community sources merge into your catalog automatically.

Files changed vs Build 92: `Harvest/HarvestTypes.swift`, `Harvest/HarvestServices.swift`,
`Harvest/HarvestModel.swift`, `Harvest/CrawlCoordinator.swift` (attribution),
`Harvest/MacHarvestBridge.swift` (attribution in notes), `Harvest/HarvestCloudSync.swift`
(attribution in uploads), `Harvest/DefaultSourceCatalog.swift` + `default-sources.json`
(110 sources), `Views/MacBrowseView.swift`, `Views/MacKitchenViews.swift`,
`Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). The 110-source catalog
round-trips through the tolerant decoder. New enum cases (`feedOnly`, `htmlListing`)
decode-degrade safely on older files via the tolerant `SourceProfile` init. URL
classification desk-checked against recipe slugs, `/category/…`, `/holidays/…`,
`/recipes/` indexes, pagination, and media files; the feed extractor against RSS,
Atom (`<link href>`), and reddit's encoded-body outbound links. **No Swift compiler
here — the real build is Xcode.**
