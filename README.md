# Stocked Recipe Manager for Mac

The recipe-only macOS companion to [Stocked for iOS](https://github.com/sahmoee/stocked).
It edits the shared recipe library, imports recipes with honest source attribution, and
syncs recipe changes with the same Stocked household used on iPhone and iPad. Inventory,
grocery, meal-planning, cooking, and analytics surfaces are intentionally absent.

## Features

- Direct import from a recipe URL, pasted recipe text, or recipe screenshots
- Explicit, adjustable scan and import batch limits instead of open-ended mining
- A persistent queue that survives app restarts and restores unfinished work after Stop
- Rate-limit deferral, dead-link removal, exact-URL duplicate skipping, and cached partial results
- Searchable filters for birthdays, drinks, holidays, cuisines, diets, seasons, and cooking methods
- A category library populated automatically as recipe sites are mined
- Source publisher and source URL fields preserved through Mac, household, Worker, and iOS sync
- Curation with guaranteed images before publish
- Cloud sync of approved recipes to the shared backend
- Native SwiftUI macOS app

## Import a recipe

1. Open **Find & Import** and use **Quick import**.
2. Paste a recipe URL, paste the recipe text, or choose one or more screenshots.
3. Review any highlighted missing or uncertain information.
4. Choose **Approve & Send to Stocked**. The recipe is added to the Mac kitchen and its
   image-complete copy is published for Stocked iOS.

If you do not have a recipe in mind, **Explore websites** can search a small batch of up
to three trusted sources. Choose optional category filters, preview individual results,
and add selections from multiple searches to one queue. Import the queue when it contains
the recipes you want; browsing does not need to run continuously. Sources that explicitly
rate-limit or block automated access are removed from automatic discovery but remain
available for direct links.

## Requirements

- Xcode 16 or later
- macOS 14 SDK

## Getting started

```bash
git clone https://github.com/sahmoee/StockedMac.git
cd StockedMac
cp Secrets.example.xcconfig Secrets.xcconfig   # fill in your values
open StockedMac.xcodeproj
```

Open the project, select the **StockedMac** scheme (mark it Shared in Xcode if it isn't
already), and run.

## Project structure

- `StockedMac/` — app sources (views, sync, kitchen tools)
- `default-sources.json` — seed recipe sources
- `worker-build/worker.py` — offline parser used to build the bundled local helper
- `scripts/harvest-recipes.py` — optional gzip-aware batch sitemap harvester

## License

See [LICENSE.md](LICENSE.md). Privacy in [PRIVACY.md](PRIVACY.md); third-party notices
in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
