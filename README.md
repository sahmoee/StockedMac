# Build 96 (4.36) — pristine Browse, hub mining, in-pane browser

**Mac delta only.** No worker or iOS change. Full `StockedMac/` folder included
(Builds 91–95 with 96 on top).

---

## The parser wasn't broken — the classifier was

Look at the failure names in your screenshot: `breakfast`, `dinner`, `lunch`,
`appetizers`, `main-dish`, `side-dishes`, `chicken`. Those are Food Network **category
hubs**, not recipes — they carry no recipe schema, so every engine truthfully failed.
Build 95's classifier let them through because they matched the source's `/recipes/`
pattern. Build 96 fixes the shape test and turns hubs from failures into leads:

- **Hub slugs are listings now.** A final path segment with no hyphen and no digits
  ("breakfast") is a hub even under `/recipes/`; real dishes look like
  `perfect-gravy-recipe-1928388`. Photo galleries and video shells are skipped outright.
- **Hubs are mined, not failed.** If a category page still reaches the importer, its
  recipe links are extracted and **join the queue automatically** at the end of the run
  (deduplicated), with a note in the summary — a wrong URL now yields recipes instead
  of a red line.
- **Wider JSON-LD hunt.** Hydration payloads (Next.js-style plain `<script>` bodies
  containing a schema.org Recipe) are now scanned too, with a string-aware balanced-JSON
  extractor — one more class of "No JSON-LD found" gone.

## Viewing pages happens in the app

The browser no longer opens as a sheet. **It takes over the Browse right pane** — press
*Open browser* in the toolbar, or *View* on any failure row, and the page renders right
there over https with the address bar on top. *Import this page* runs the normal
pipeline; the ⌄ menu force-imports a page the category detector reads wrong (which
queues the hub's recipes instead if it really is one); *Add to queue* files the URL;
*Close* returns to the activity pane.

## Twenty ways recipe browsing & importing got better

1. Hub-slug classification — "breakfast"-style URLs can't masquerade as dishes.
2. Digit-slugs (`…-recipe-1928388`) recognized as dishes even without hyphen rules.
3. Category pages hit at import are mined for their recipe links.
4. Mined links auto-join the queue, deduplicated, in one batch at run end.
5. Mined counts appear in the run summary and Activity.
6. Photo/gallery/video URLs skipped before they waste a request.
7. JSON-LD found inside plain `<script>` hydration payloads.
8. String-aware balanced-JSON extraction (braces inside strings can't fool it).
9. The in-app browser is in-pane — no sheet, no window juggling.
10. Failure rows: slug + site + the first engine's verdict, one line each.
11. The pipe-chain of every fallback's echo is gone from failure rows.
12. *View* on a failure opens that exact page in-pane, pre-filled.
13. Force-import for pages the detector reads wrong — and even that path mines hubs.
14. Single-page imports (`Import this page`) select the new draft in Harvest.
15. Right-pane content keeps a readable measure (920 pt cap) on wide windows.
16. Toolbar browser button toggles — it reads "Close browser" while open.
17. A fresh address gets a fresh browser panel (no half-navigated leftovers).
18. Browser works at any pane size (minimum lowered for the embedded case).
19. Import-anyway is disabled mid-run, so it can't pile onto an active batch.
20. Classification improvements feed discovery too — sitemap walks now route hubs to
    link-mining instead of the candidate list, so "288 candidates" means 288 dishes.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`.
2. Build Settings: `MARKETING_VERSION = 4.36`, `CURRENT_PROJECT_VERSION = 96`.
3. Clear the queue and browse Food Network again — the hub URLs won't be queued at
   all this time, and any that remain get mined into real recipes.

Files changed vs Build 95: `Harvest/HarvestServices.swift` (classifier, script-JSON
scan), `Harvest/HarvestTypes.swift` (listingPage error), `Harvest/CrawlCoordinator.swift`
(hub mining), `Harvest/HarvestModel.swift` (mined-queue handling, importPage),
`Views/MacBrowserPanel.swift` (embeddable, force-import), `Views/MacBrowseView.swift`
(in-pane browser, failure rows, measure), `Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). The classifier was
desk-checked against the nine failing slugs from the screenshot (all → listing), real
FN dish URLs (→ recipe), Allrecipes `/recipe/12345/name/` (→ recipe), and gallery URLs
(→ skip). The balanced-JSON extractor was traced against nested objects and braces in
strings. **No Swift compiler here — the real build is Xcode.**
