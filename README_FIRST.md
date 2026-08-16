# Read me first

StockedMac is the recipe-only companion to Stocked iOS. It imports, repairs, edits, categorizes, images, and publishes recipes; do not restore inventory, grocery, meal-planning, cooking, or analytics features. Imported recipes require a usable image and original source attribution.

`Secrets.xcconfig` is local and ignored. Production sync uses `https://api.sowensstudios.com`. Preserve partial scan results, resumable queues, limits, deduplication, and retroactive repair. Verify the `StockedMac` scheme.

The normal Find flow is hands-off: discovery imports immediately, complete image-backed recipes approve and publish automatically, and only incomplete records wait for attention. Preserve original image bytes and URLs; never introduce lossy sync re-encoding.
