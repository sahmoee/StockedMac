# Build 98 (4.38) — queue control: convergence, dedupe, and stopping on your terms

**Mac delta only.** No worker or iOS change. Full `StockedMac/` folder included
(Builds 91–97 with 98 on top).

---

## Why the queue snowballed

Build 96's mining had no memory: every category page yielded links, some of those links
were *more* category pages, and the next round mined them too — 288 candidates became
1,662 queued URLs, with no way to tell what was new, duplicate, or already yours.

## What Build 98 does

**Mining converges now.**

- **One generation deep.** A link that arrived by mining never mines again. A mined
  link that turns out to be another category page is noted and dropped, not expanded.
- **Session memory.** Every mined link is remembered for the session — the same URL
  can never join the queue twice, across any number of rounds.
- **Library check.** Mined batches are filtered against recipes you already have
  before they join (with a count of what was dropped).
- **Queue cap.** A hard ceiling (default 500, stepper in the Queue card, 100–5,000).
  When mined links would push past it, they're left out with a clear warning instead
  of silently piling on. An over-cap banner appears on the card.

**Duplicates became answerable.**

- **Clean button** on the Queue card: removes exact duplicates, everything already in
  the library, and everything that failed this session — then reports exactly what it
  removed ("kept 214 — removed 96 duplicates, 1,301 already imported, 51 failed
  earlier").
- **Imports skip the library first.** Before a run spends a single request, URLs
  already imported are dropped and counted ("Skipped 1,301 already in the library") —
  re-importing a big queue costs only what's actually new.

**Stopping midway means keeping what you have.**

- Stop during an import: everything imported so far is kept and reloaded; freshly
  mined leftovers are **discarded with a note** instead of swelling the queue behind
  your back.
- Stop during a browse: the engines return everything found up to that moment as a
  normal session report — *Queue verified links* works on a partial run, and the
  session lands in history like any other.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/`.
2. Build Settings: `MARKETING_VERSION = 4.38`, `CURRENT_PROJECT_VERSION = 98`.
3. Press **Clean** on your 1,662-URL queue first — expect it to shrink dramatically —
   then Import what remains.

Files changed vs Build 97: `Harvest/HarvestTypes.swift` (queueCap),
`Harvest/HarvestModel.swift` (mining convergence, session memory, library skip,
clean queue, cancel semantics), `Views/MacBrowseView.swift` (Clean button, cap
stepper, over-cap banner), `Core/MacBuildConfig.swift`.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). The convergence
argument: mined set is session-global and checked at record-time AND flush-time, so
the mined-link population is monotone and bounded by the cap; second-generation
mining is structurally impossible. Cancel paths traced for mined-discard and
partial-report survival. **No Swift compiler here — the real build is Xcode.**
