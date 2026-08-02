# Build 99 (4.39) — bulk verify that mines, and batch sizes you control

**Mac delta only.** No worker or iOS change. Full `StockedMac/` folder included
(Builds 91–98 with 99 on top).

---

## Bulk verify walks into category pages now

Your last pass removed 15 URLs as "not a recipe page". Some of those were hubs full of
recipes. Bulk verify now judges each queued URL three ways:

- **Recipe** → kept, as before.
- **Category page** → **replaced by the recipes found on it — and on up to five of its
  sub-pages** (a "breakfast" hub's sub-categories get mined too). Bounded at 80 links
  per hub, deduplicated against the queue, this session's mining, and the unchecked
  remainder, then capped at the queue cap — the convergence rules from Build 98 all
  apply, so this cannot re-open the snowball.
- **Neither** → removed, counted.

Bot-walled pages get the WebKit-rendered look before judgment, same as importing. The
summary line says exactly what happened: "Verified 100: kept 74, mined 212 from 9
category pages, removed 5 · 66 unchecked stay queued".

## The three dials

| Dial | Where | What it does |
|---|---|---|
| **Verify up to N per pass** (25–1,000) | Verification card | One Bulk-verify press checks the front N of the queue; the rest stay queued unchecked |
| **Import batch** (All, or 50–2,000) | Queue card | One Import press takes the first N and leaves the rest for the next press; the button says "Import first 200 of 1,204" |
| **Queue cap** (100–5,000) | Queue card | From Build 98 — the ceiling mined/discovered links respect |

## Import drains the queue now

Taken URLs leave the queue text the moment a run starts — the sidebar count finally
means "waiting to import", not "everything ever found". Stopped runs keep what
imported; the un-taken remainder is still sitting in the queue untouched.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`.
2. Build Settings: `MARKETING_VERSION = 4.39`, `CURRENT_PROJECT_VERSION = 99`.
3. Try: set Import batch to 50, Bulk verify the queue (watch hubs convert to mined
   dishes), then press Import a few times and watch the count actually go down.

Files changed vs Build 98: `Harvest/HarvestTypes.swift` (two batch settings),
`Harvest/CrawlCoordinator.swift` (`verifyOrMine` with sub-page expansion),
`Harvest/HarvestModel.swift` (mining bulk verify, draining batched imports),
`Views/MacBrowseView.swift` (steppers, dynamic Import button),
`Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). The merge order in
bulk verify (kept + fresh-mined + unchecked remainder) was traced for dedupe,
session-set, cancel-mid-pass, and cap-overflow cases; `verifyOrMine`'s sub-page walk
is bounded (5 pages, 80 links) and cancellation-checked. **No Swift compiler here —
the real build is Xcode.**
