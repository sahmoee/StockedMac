# StockedMac Fix + Documents Cleanup Report — Aug 1, 2026

## Build errors fixed (written directly to your Mac)

1. **RecipeStore actor-isolation error** — `refreshFingerprint()` in `HarvestTypes.swift` is now explicitly `nonisolated`, so the `RecipeStore` actor (and `CrawlCoordinator`) can call it synchronously. With the project's default actor isolation set to MainActor, the method was being treated as main-actor-isolated.
   - File: `Documents/Stocked Mac/HarvestTypes.swift` (line 86)

2. **"UsersDownloadsremove-sowens-recipes.sh couldn't be opened"** — the Xcode project had a Resources build-phase entry for a stray file literally named `Users$(whoami)Downloadsremove-sowens-recipes.sh`. Xcode expands `$(whoami)` as an (empty) build setting, so it looked for `UsersDownloadsremove-sowens-recipes.sh`, which doesn't exist. All references were removed from `project.pbxproj`, and the stray file itself was moved to `_to_delete`. The dead `README.md` reference was also removed (the README was part of the aggressive doc cleanup).
   - File: `Documents/Stocked Mac/StockedMac.xcodeproj/project.pbxproj`

3. **"Command Ld failed"** — most likely a knock-on effect of the failing resource/compile phases above. If it persists after a clean build (Product → Clean Build Folder, then build), let me know and I'll dig into the link log.

The `fixed-files/` folder in this zip contains copies of the two updated files for reference — the live versions are already saved on your Mac.

## Cleanup — 113 items moved to `Documents/_to_delete` (~2.6 GB)

I can't permanently delete files on your Mac, so everything was moved (folder structure preserved) into `Documents/_to_delete`. Review it and drag it to the Trash to reclaim the space.

What was moved, per your "aggressive" choice:

- **Rebuildable build junk**: `.venv` + `.pyinstaller` in both `Stocked 2/worker-build` and `Stocked Mac/worker-build`; `worker/node_modules` and `worker/.build`; `BuildBuddy/.build`; three DerivedData dumps under `Codex/2026-08-01`.
- **Backups**: every `.buildbuddy-backups` folder (Stocked 2, Stocked Mac, Reel, Atlas, Astra, BuildBuddy, site-repo, The SESH.).
- **Xcode user state**: all `xcuserdata` folders (7 projects).
- **Finder junk**: 17 `.DS_Store` files.
- **Big archive**: `Stocked Mac.zip` (72 MB).
- **Broken script**: `Stocked Mac/Users$(whoami)Downloadsremove-sowens-recipes.sh`.
- **Docs/notes (.md/.txt)**: all READMEs, CHANGELOGs, IMPLEMENTATION/APPLY/AUDIT/NOTES/HANDOFF files across every project (63 files). Kept: `requirements.txt` files (needed for worker builds), `.gitignore`, and everything inside `.git`.

## To rebuild later if needed

- `worker`: run `npm install` to restore `node_modules`.
- `worker-build` folders: recreate the venv with `python3 -m venv .venv && pip install -r requirements.txt`.

## Note on Xcode MCP

No Xcode MCP tools are reachable from this session (I checked), so I couldn't run a build to verify — the fixes were made directly to the source and project files. If you've installed an Xcode MCP in the desktop app, it isn't being bridged into this session; try toggling it in the desktop app's connector settings, or just hit ⌘B in Xcode.
