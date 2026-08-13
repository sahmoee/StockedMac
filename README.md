# Stocked for Mac

The macOS companion to [Stocked for iOS](https://github.com/sahmoee/stocked). It
discovers and browses recipes from the web, curates them with images, and publishes the
approved set to the shared backend so the iOS app can pull them into its recipe pool.
The fastest path is deliberately short: import one recipe, review it, then approve it.

## Features

- Direct import from a recipe URL, pasted recipe text, or recipe screenshots
- Optional small-batch website discovery instead of open-ended mining
- Curation with guaranteed images before publish
- Cloud sync of approved recipes to the shared backend
- Native SwiftUI macOS app

## Import a recipe

1. Open **Browse** and use **Quick import**.
2. Paste a recipe URL, paste the recipe text, or choose one or more screenshots.
3. Review any highlighted missing or uncertain information.
4. Choose **Approve & Send to Stocked**. The recipe is added to the Mac kitchen and its
   image-complete copy is published for Stocked iOS.

If you do not have a recipe in mind, **Explore websites** can search a small batch of up
to three trusted sources. Select the results you want and import them directly; browsing
does not need to run continuously.

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

## License

See [LICENSE.md](LICENSE.md). Privacy in [PRIVACY.md](PRIVACY.md); third-party notices
in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
