# Changelog

Every push should add an entry here so GitHub carries the build/change history.
Newest at the top. Keep it plain ASCII (see .gitmessage.txt for the commit rules).

## Build 105 — Version 4.43

- Fixed valid JSON-LD recipe pages being mistaken for category pages when they also linked to related recipes.
- Added a searchable category filter for occasions, drinks, holidays, cuisines, diets, methods, and seasons.
- Found recipes from multiple websites now accumulate in one explicit import queue before processing.
- Access-limited, paywalled, robots-blocked, and rate-limited sources leave automatic discovery while direct import remains available.
- Hardened the native fetch headers, bundled Python JSON-LD/recipe-card fallbacks, and gzip-aware batch harvesting script.

## Build 104 — Version 4.43

- Build 104 keeps version 4.43 and redesigns recipe import around a three-step guided flow.
- Added direct one-recipe URL import, pasted recipe parsing, and screenshot text recognition.
- Made website discovery optional, limited each pass to three sources, capped visible results to a focused batch, and removed the extra queue step for selected recipes.
- Added review search, sorting, attention filters, readiness checks, and explicit Approve & Send delivery into the Mac kitchen and Stocked iOS harvest sync.
- Normalized more tracking parameters before importing recipe URLs.
