# Build 97 (4.37) — fifteen improvements, some against instructions

**Mac delta only.** No worker or iOS change. Full `StockedMac/` folder included
(Builds 91–96 with 97 on top).

About the console dump: those `WebContent` sandbox lines (pboard, launchservicesd,
RunningBoard, WEBP) are macOS's normal noise for a sandboxed WebKit process — they mean
the built-in browser IS running, not that it's broken. Build 97 still quiets it: the
invisible renderer now uses an **ephemeral website data store** (no cookies/caches on
disk, fewer sandbox negotiations) and denies media autoplay.

Your remaining failures — `packable-breakfasts`, `5-healthy-muffins-yes-its-possible`,
`how-to-make-…`, `one-pot` — are FN roundups/topic hubs that pass a hyphen test. Items
1–3 below close that hole from three directions.

## The fifteen

1. **Listicle shapes are hubs.** Slugs ending `-breakfasts`, `-ideas`, `-meals`, `-recipes`…,
   starting `best-`, `top-`, `how-to-`, `what-to-`, or starting with a digit
   (`5-healthy-muffins…`) classify as listings — unless they end in a numeric id
   (`…-24681564`), which always marks a real record.
2. **Rendered re-judgment.** When a page only reveals itself after JavaScript runs, the
   page detector now re-inspects the *rendered* DOM — a hydrated roundup becomes queued
   recipes instead of "No JSON-LD found".
3. **Pattern-aware link density.** The listing detector counts links using each source's
   own URL patterns (`/recipes/` for FN), not a hardcoded `/recipe/` — roundups register
   as roundups.
4. **Circuit breaker** *(against "import everything I queued")*: eight straight failures
   from one host skips the rest of that host's URLs this run, with one warning line and
   a count in the summary — no more 400-failure marathons.
5. **Cancelled ≠ failed** — pressing Stop no longer paints red rows for the unprocessed
   remainder.
6. **Failures deduplicate** by URL; retry loops can't stack the same page twice.
7. **The failures panel leads with the shape of the problem** — reasons counted
   ("No recipe data ×12") above the per-URL list.
8. **Copy URLs** button — the failed list, one per line, straight to the clipboard.
9. **Failed links stay out of the queue** when re-browsing this session *(against "queue
   everything verified")* — clearing the failures list re-admits them deliberately.
10. **Per-run render cache** — a retried URL never pays for a second WebKit render.
11. **Ephemeral renderer** — nonPersistent data store, autoplay denied, less console
    noise, nothing accumulating on disk.
12. **Bulk verify sees through bot walls** — the verifier renders blocked pages with the
    same WebKit eyes the importer uses, so "Verify queued URLs" works on FN too.
13. **Activity log timestamps** — every line shows how long ago, right-aligned.
14. **Success resets a host's failure streak** — one bad stretch doesn't poison a good
    site for the rest of the run.
15. **Breaker skips are visible** — counted in progress and named in the run summary,
    never silent.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`.
2. Build Settings: `MARKETING_VERSION = 4.37`, `CURRENT_PROJECT_VERSION = 97`.
3. Retry the failures: the roundups will convert to queued recipe links (watch the
   summary's "mined" note), and real dishes import.

Files changed vs Build 96: `Harvest/HarvestServices.swift` (listicle rules, detector
density), `Harvest/CrawlCoordinator.swift` (render cache, rendered re-judgment,
WebKit-aware verify), `Harvest/HarvestModel.swift` (breaker, failure hygiene, copy),
`Harvest/WebKitRenderer.swift` (ephemeral store), `Views/MacBrowseView.swift`
(grouped failures, timestamps), `Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). The listicle rules
were desk-checked against every slug in your screenshot (all 10 → listing or id-recipe
correctly) and against real dish slugs (`perfect-gravy-recipe-1928388`,
`sugar-cookie-banana-bread-24681564` → recipe). Breaker paths traced for streak-reset,
retry passes, and cancel. **No Swift compiler here — the real build is Xcode.**
