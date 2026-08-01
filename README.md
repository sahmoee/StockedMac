# Build 90 (4.30) — Mac only: recipe housekeeping you can actually find

**This package is the Mac delta only.** Nothing in it belongs in the iOS project, and no
iOS file is included. The iOS app is unaffected and stays on Build 89 / 4.29.

---

## Why you couldn't find either option

Both features existed. Neither was anywhere you would look.

**Removing recipes with a matching spreadsheet** shipped in Build 88 as two File-menu
items — *Export recipes as CSV…* and *Remove recipes from a CSV…*. The File menu is the
right home for import and export and the wrong home for tidying up, and if the Build 88
Mac files were never copied into your tree, the items are not there at all.

**Removing the Kaggle and Sowens recipes** shipped in Build 89 as a silent sweep that runs
at launch. It has no button, no menu item and no message. Working exactly as designed, it
is indistinguishable from not being installed.

This build puts all three actions in **Settings ▸ Data**, in a new *Recipes* section
directly under the counts, and adds the retired-source removal to the File menu as well.

---

## Files

| File | New / Revised | What changed |
|---|---|---|
| `StockedMac/Views/MacRecipeMaintenance.swift` | **New** | The three jobs — export, remove-by-spreadsheet, remove-retired-sources — in one place so the menu and Settings share them. |
| `StockedMac/Views/MacRecipeMaintenanceSection.swift` | **New** | The *Recipes* block in Settings ▸ Data. Self-contained; one line drops it into any Form. |
| `StockedMac/Views/MacSettingsView.swift` | Revised | One line added to the Data form. **Read the note below before copying this file.** |
| `StockedMac/Views/MacCommands.swift` | Revised | The two CSV items now call the shared helper; adds *Remove Kaggle and Sowens recipes…*. |
| `StockedMac/Core/MacBuildConfig.swift` | Revised | 89/4.29 → **90/4.30**, new `buildName`. |
| `StockedMac/Core/MacRecipeCSV.swift` | Unchanged (Build 88) | Included so this package works even if Build 88's Mac half was never copied in. |
| `StockedMac/Core/MacRecipeSourceBlocklist.swift` | Unchanged (Build 89) | Same reason. |
| `StockedMac/StockedMacApp.swift` | Unchanged (Build 89) | Same reason — it carries the launch sweep. |

The last three are byte-identical to what was already sent. They are here so you can copy
the folder over and be done, rather than checking which earlier package landed.

---

## Read this before copying `MacSettingsView.swift`

Your screenshot shows Settings with three tabs: **General, Data, About**. The copy
included here matches that exactly — it is your file with one line added.

Some Stocked Mac trees have a fourth **Account** tab (Sign in with Apple, added in Build
78). **If your Settings window has an Account tab, do not copy the included
`MacSettingsView.swift`** — it would delete that tab. Instead open your own copy, find the
Data form, and paste one line above the `Section` whose header is `Starting over`:

```swift
            MacRecipeMaintenanceSection()

            Section {
                HStack {
                    Button("Load a sample kitchen…") { confirmSample = true }
```

That is the entire change to that file. Everything else in this package applies either
way.

---

## Installing

1. Copy `StockedMac/` over the Mac tree, keeping the folder structure — minus
   `MacSettingsView.swift` if the note above applies to you. The project uses Xcode
   synchronized folders, so the two new `.swift` files compile just by being on disk;
   there is no target-membership step.

2. **Set the version in Build Settings.**

   ```
   MARKETING_VERSION       = 4.30
   CURRENT_PROJECT_VERSION = 90
   ```

The iOS target keeps `4.29` / `89`. The two apps are separate products with separate
version lines, and this build changes nothing on the phone.

---

## What you get

### Settings ▸ Data, new *Recipes* section

*Export recipes as a spreadsheet…* writes one row per recipe, both libraries, with a
`remove` column. *Remove recipes from a spreadsheet…* takes that file back, matches the
ticked rows against your library, and shows you every match — including the ambiguous and
the unmatched — before anything goes.

*Remove N retired-source recipes…* is the third button, and **the number is in the label**.
That is the part worth having: a button that says "No retired-source recipes to remove"
and sits greyed out tells you the sweep already did its job, which is the one thing the
silent Build 89 version could never tell you. If it shows a count, pressing it names the
breakdown, asks, saves a restorable copy, and then removes them.

### File menu

*Export recipes as CSV…* and *Remove recipes from a CSV…* stay exactly where they were —
anyone who has learned them keeps them — and *Remove Kaggle and Sowens recipes…* joins
them. The bodies moved into `MacRecipeMaintenance`; the menu no longer owns the code.

---

## What the counts will probably say

Your Data pane reads **102 recipes**. If Build 89's Mac half is already in your tree and
the app has been launched since, the Kaggle and Sowens recipes are gone from that 102
already, and the new button will be greyed out saying there is nothing to remove. That is
the correct result, not a failure — and it is now legible instead of invisible.

If the button shows a count instead, Build 89's Mac half never made it in. Copying this
package fixes that too, because `MacRecipeSourceBlocklist.swift` and `StockedMacApp.swift`
are included.

---

## The thing not to refactor

**Every removal path here goes through `MacKitchenStore.deleteRecipe(ids:)` and
`deleteSavedRecipes(ids:)`, or the next household pull puts everything back.**

The Mac has no `didSet` observers — `@Observable` rewrites stored properties into
accessors, which property observers cannot coexist with — so the household tombstone
bookkeeping lives inside those two methods, which call `sync?.noteRecipeDeleted(_:)` and
`noteSavedRecipeDeleted(_:)`. Filtering `store.recipes` in place would remove the recipes
locally, leave no tombstone, and the next pull would restore all of them.

`MacRecipeMaintenance.removeRetiredSources` deliberately does **not** call
`MacRecipePurge.run`. That path is right for a silent launch sweep — no confirmation, no
backup, no window — and wrong for a button somebody pressed. The manual version counts
first, says what it found, waits for a yes, and routes through
`MacRecipeCSV.remove(recipeIDs:savedRecipeIDs:store:)`, which writes a restorable copy on
the way past. Both end at the same two store methods, so the tombstones are recorded
either way. Keep both; they are not duplicates.

**Three copies of the blocklist rules exist and must agree**:
`MacRecipeSourceBlocklist.swift` here, `RecipeSourceBlocklist.swift` in the iOS project,
and the constants atop `stocked-purge-recipes.py` from the Build 89 Mac package. Change
one, change all three.

---

## What is matched, and what is deliberately not

A recipe is judged **only by where it came from**: source name, source or image URL, ID
prefix, and tags. Titles, ingredients and steps are never read. A recipe called "Kaggle
Chicken Curry" that you typed yourself survives. Tags are matched by whole-tag equality,
not substring, so a hand-written recipe tagged `kaggle-style` is safe.
`MacBuildConfig.company` is `"Sowens Studios"` — brand, not a recipe source. Nothing in
the blocklist reads it, and nothing should.

---

## Verification done here

Every Swift file brace-, paren- and bracket-balanced. Every symbol the new code calls was
resolved against the real tree: `MacRecipeCSV.exportFilename()` / `.exportCSV(store:)` /
`.plan(from:store:)` / `.remove(recipeIDs:savedRecipeIDs:store:)`,
`MacRecipeCSVWindow.confirm(plan:)`, `MacRecipeSourceBlocklist.isBlocked(_:)` for both
`UserRecipe` and `GeneratedRecipe`, and `MacKitchenStore.recipes` / `.savedRecipes` /
`.deleteRecipe(ids:)` / `.deleteSavedRecipes(ids:)` / `.storageDirectory` /
`.lastSavedAt` / `.lastSaveError`. The two new top-level type names
(`MacRecipeMaintenance`, `MacRecipeMaintenanceSection`) were checked for collisions across
every Stocked tree. The included `MacSettingsView.swift` was confirmed to reference
neither `MacAppleAuth` nor `AuthenticationServices`, so it cannot drag in a dependency
your tree may not have.

**There is no Swift compiler here — the real build is Xcode on your Mac.**

---

## Still outstanding on your side

`RecipeDraft` needs `nonisolated` on its declaration in whichever file now holds it:

```swift
nonisolated struct RecipeDraft: Identifiable, Codable, Hashable, Sendable {
```

Without it, the Mac target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes
`refreshFingerprint()` main-actor-isolated and `actor RecipeStore.merge()` cannot call it.
Do not add `await` at the call site — a `mutating` call on a value type inside an actor
cannot be awaited. `ParserResult`, `IngredientSection`, `InstructionSection`, `RecipeTimes`
and `AppSettings` want the same marker.
