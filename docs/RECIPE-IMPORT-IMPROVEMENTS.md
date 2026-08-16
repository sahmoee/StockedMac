# Recipe Import Improvement Pass

Build 110 implements these twenty changes to simplify intake and retain more valid recipes:

1. Images are a hard requirement before a recipe enters the shared library.
2. Missing images remain visible in Review and block approval until recovered.
3. Worker payloads never publish recipes with missing images or broken image routes.
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

Mined categories are also enriched with cuisine and diet labels when recipes cross into the shared Mac/iOS model. All limits remain adjustable in Find & Import, cancellation remains recoverable, rate-limited URLs remain deferred rather than retried in a loop, and image-less recipes never cross app or cloud boundaries.

## Making future fixes retroactive

Every historical repair is versioned by `HarvestModel.currentRecipeRepairRevision`. Revision 3 enriches both Mac drafts and shared iOS recipes with canonical categories inferred from their structured metadata, title, and source URL; category pages remain discovery containers, never recipe records. When a future model, parser, normalization, attribution, category, or image fix should apply to existing data:

1. Add the local transformation to `RecipeStore.repairExisting()` and/or `HarvestModel.repairSharedRecipeLibrary()`.
2. Increment `HarvestModel.currentRecipeRepairRevision`.
3. Build and launch. The app repairs local records once, seeds every historical HTTP source into `retroactive-refresh.txt`, and reparses that durable backlog in adjustable finite batches.
4. Verify the Recipe Sync screen reaches zero historical sources. Stop is safe: unfinished URLs remain on disk and resume later.

Stocked iOS independently reruns missing-image backfill on every launch until no further progress is possible, so improvements to its image resolver also apply to older database recipes.
