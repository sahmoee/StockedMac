# Recipe Import Improvement Pass

Build 110 implements these twenty changes to simplify intake and retain more valid recipes:

1. Recipes no longer require an image to enter the shared library.
2. A missing image is advisory in review instead of blocking approval.
3. Worker payloads omit the local image route when no local image exists, avoiding broken thumbnails.
4. Automatic image recovery runs before approved recipes are handed to the shared library.
5. One valid ingredient is sufficient for a structurally complete recipe.
6. One valid method step is sufficient for a structurally complete recipe.
7. Generic attribution is flagged for review but no longer discards otherwise valid recipe content.
8. Extra quality recommendations no longer block automatic approval by default.
9. The default automatic-approval confidence threshold is reduced from 90% to 78%.
10. Image-download, WebKit-fallback, and Web Story notices no longer block automatic approval.
11. Queue imports skip the redundant verification pass by default; the importer still detects and mines listing pages.
12. Four independent hosts can import concurrently by default.
13. The default finite import batch is increased from 25 to 50 recipes.
14. The default finite scan target is increased from 50 to 100 recipes.
15. The durable queue capacity is increased from 500 to 2,000 unique URLs.
16. Manual bulk verification can process 200 queued URLs per pass.
17. A browse pass can combine up to five selected sources instead of three.
18. Sitemap, category, and feed engines now accumulate results without reopening categories already mined in the same pass.
19. URL normalization strips a broader set of advertising and newsletter parameters before deduplication.
20. Identical recipe content now merges by content fingerprint, while same-title recipes from different sources remain allowed.

Mined categories are also enriched with cuisine and diet labels when recipes cross into the shared Mac/iOS model. All limits remain adjustable in Find & Import, cancellation remains recoverable, and rate-limited URLs remain deferred rather than retried in a loop.
