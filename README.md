# Stocked for Mac

The macOS companion to [Stocked for iOS](https://github.com/sahmoee/stocked). It
discovers and browses recipes from the web, curates them with images, and publishes the
approved set to the shared backend so the iOS app can pull them into its recipe pool.

## Features

- Web recipe discovery and browsing
- Curation with guaranteed images before publish
- Cloud sync of approved recipes to the shared backend
- Native SwiftUI macOS app

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
