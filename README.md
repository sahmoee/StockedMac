# Build 92 (4.32) — multi-select sources, list updates from a file, and the self-heal

**Mac delta only.** No worker or iOS change — the Build 91 worker deploy still covers
everything here. The whole `StockedMac/` folder from Build 91 is included again with the
Build 92 changes on top, so copying this one package over your tree lands you correct even
if part of Build 91 was missed.

---

## Why your screenshot still said "0 sites"

Build 91 made the catalog impossible to *lose* — but only for a `sources.json` that was
missing, empty, or corrupt. Your Mac has a `sources.json` that decodes fine and contains
entries that can't browse (or an install where the new Harvest files didn't all land), so
the registry trusted it and the screen showed 0 sites with nothing to click.

Build 92 stops trusting that state:

- **Self-heal at launch.** If, after loading and merging, not one source is enabled and
  browsable, the app restores the built-in catalog automatically — keeping any custom or
  imported sources — and says so in the Activity log.
- **A Restore button in the error row.** "No sources loaded" is now next to
  *Restore built-in catalog* instead of directions to another screen.

Relaunch once after installing and the hundred sites appear.

## The dropdown is now a multi-select checklist

The Sources control opens a popover checklist: search by name, tag or domain; group
headers (Recent / American — Top 50 / Worldwide — Top 50 / Custom & imported) each with an
All/None toggle; health dots per site; a running "N selected" count with All-shown/None.

The action buttons follow the selection:

| Selection | Buttons |
|---|---|
| one site | Browse & Import · Queue only |
| several | **Browse N sources** · Queue from N — visits each site in turn, chaining after each import finishes; a "still to visit" row shows progress with *Stop after this* |
| none | Next in rotation · Auto-rotate N (as before) |

## Update the source list from a file

Two new buttons in the Sources header (plus Restore):

- **Import (↓)** — pick a `.txt`, `.csv` or `.json` file:
  - **Plain text / CSV** — one site per line: a URL or bare domain, or `Name | url`,
    `Name, url`, `Name<TAB>url`. `#` and `//` lines are comments. Each becomes an
    enabled, sitemap-browsing source (id `imported-<domain>`), deduplicated by domain.
  - **JSON** — an array of full source profiles (the exact `sources.json` /
    `default-sources.json` shape), tolerant per element. Matching ids update in place,
    new ids are added — so a file import can also *edit* built-in sources.
- **Export (↑)** — writes the current catalog as `stocked-sources.json`, which the
  importer reads back. Export → edit → import is the round-trip for maintaining the list.

## Installing

1. Copy `StockedMac/` over `Documents/Stocked Mac/StockedMac/` (folder structure kept).
2. Build Settings: `MARKETING_VERSION = 4.32`, `CURRENT_PROJECT_VERSION = 92`.
3. Launch once — watch Activity report the catalog restore if your tree needed it.

Files changed vs Build 91: `Views/MacBrowseView.swift`, `Harvest/HarvestModel.swift`,
`Harvest/HarvestServices.swift`, `Core/MacBuildConfig.swift`. Everything else in the
package is byte-identical to Build 91.

## Verification done here

All Swift files brace/paren/bracket-balanced (raw-string aware). New symbols resolved
against the tree: `SourceRegistry.save(all:)` and the new `repairCatalog()`,
`JSONCoding.encoder()`, `LossyArray`, `SourceProfile` memberwise init,
`NSOpenPanel`/`NSSavePanel` usage mirrors `MacRecipeMaintenance`'s. The text-file parser
was desk-checked against `url`, `domain.com`, `Name | url`, `Name, url`, tab-separated,
comment and duplicate lines. **No Swift compiler here — the real build is Xcode.**
