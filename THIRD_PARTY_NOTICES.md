# StockedMac Third-Party Notices

## Cooklang Federation connection — September 5, 2026

Thanks to the Cooklang Federation contributors (https://github.com/cooklang/federation) and
the community index at https://recipes.cooklang.org. Stocked's original HTTP client reads the
documented search and recipe endpoints. No Federation server code, assets, database or package
is bundled. The upstream server is GPLv3: https://github.com/cooklang/federation/blob/main/LICENSE.
That license does not license indexed recipes. Private imports retain recipe-declared credits and
separately identify collection curators. Public sharing is disabled for this connection.

## Recipe export compatibility

The original Swift migration readers acknowledge Mealie, Tandoor Recipes, Paprika Recipe Manager
and Recipya. `KITCHEN_MIGRATION_FORMATS.md` records supported formats and pinned producer references.
No code or artwork from those applications is bundled by these readers. Referenced Mealie source
uses AGPLv3, Tandoor uses AGPLv3 with Commons Clause, and Recipya uses GPLv3; Paprika is proprietary.
Those software licenses do not license imported recipes or photos. Retain each creator's actual
credits and require the existing public-sharing permission before catalogue publication.

## Archive migration and watched folder (September 5, 2026)

The bounded archive reader and recipe migration adapters are independently written Swift.
They read documented export formats from Mealie, Tandoor Recipes, Paprika Recipe Manager and
Recipya; no application source from these projects is copied or linked. Recipe authors and image
owners retain their rights. Original author, source, supplied license and photo credits travel with
each reviewed recipe; importing an archive does not grant public redistribution permission.

ZIP format credit: **PKWARE**, [APPNOTE ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
Deflate/gzip decoding uses Apple's system-provided zlib, by **Jean-loup Gailly and Mark Adler**,
under the [zlib license](https://zlib.net/zlib_license.html). No separate zlib copy is bundled by
this batch. These links also appear in File → Import Center → Portable recipes.

The folder inbox uses Apple's security-scoped bookmarks and reads only the folder selected by
the user. It queues file metadata and hashes locally; it neither uploads nor approves recipes.

## Portable recipe files (September 5, 2026)

The new Swift file importer/exporter is original code, adding no packaged dependency. It credits
the **Cooklang contributors** for the supported recipe format (https://cooklang.org/docs/spec/;
MIT specification repository https://github.com/cooklang/spec) and **Schema.org contributors** for
the Recipe vocabulary (https://schema.org/Recipe). No Cooklang parser source is bundled. The shared
Swift Cooklang implementation is maintained identically in Stocked iOS and StockedMac.

Recipe authors, publisher links, supplied license terms and image credits are displayed during
review and retained through exports/publication. Raw imported files and their arbitrary metadata
remain private. A file or source URL does not confer redistribution rights; public import requires
the operator's explicit sharing/rights confirmation. Text exports keep photo URLs/credits; full
application backups retain the photo assets. Credits are visible in File → Import Center.

Mealie, Tandoor Recipes, KitchenOwl and Grocy informed the portability and review workflow;
their application code is not copied or bundled by this batch. Existing components below keep
their own notices and license requirements unchanged.

StockedMac bundles a local recipe parser built with Python and the packages below. Each project remains governed by its own license. Exact source versions are recorded in the release build environment and should be archived with each release.

| Component | Audited version | License |
|---|---:|---|
| Python | 3.14 | Python Software Foundation License |
| recipe-scrapers | 15.11.0 | MIT |
| beautifulsoup4 | 4.15.0 | MIT |
| soupsieve | 2.9.1 | MIT |
| requests | 2.34.2 | Apache-2.0 |
| urllib3 | 2.7.0 | MIT |
| certifi | 2026.7.22 | MPL-2.0 |
| charset-normalizer | 3.4.9 | MIT |
| idna | 3.18 | BSD-3-Clause |
| extruct | 0.18.0 | BSD-3-Clause-compatible project license; verify packaged license text at release |
| lxml | 6.1.1 | BSD-3-Clause |
| lxml-html-clean | 0.4.5 | BSD-3-Clause |
| html5lib | 1.1 | MIT |
| html-text | 0.7.1 | MIT |
| webencodings | 0.5.1 | BSD |
| rdflib | 7.6.0 | BSD-3-Clause |
| pyRdfa3 | 3.6.5 | W3C-compatible project license; verify packaged license text at release |
| mf2py | 2.0.1 | MIT |
| isodate | 0.7.2 | BSD-3-Clause |
| pyparsing | 3.3.2 | MIT |
| six | 1.17.0 | MIT |
| w3lib | 2.4.1 | BSD-3-Clause |
| typing-extensions | 4.16.0 | PSF-2.0 |
| packaging | 26.2 | Apache-2.0 OR BSD-2-Clause |
| PyInstaller bootloader | 6.21.0 | GPL-2.0-or-later with the PyInstaller exception permitting distribution of non-free programs |
| altgraph | 0.17.5 | MIT |
| macholib | 1.16.4 | MIT |

License files installed with the audited environment are preserved under `worker-build/.venv` during development. Authoritative project/source pages include:

- <https://www.python.org/about/legal/>
- <https://github.com/hhursev/recipe-scrapers>
- <https://www.crummy.com/software/BeautifulSoup/>
- <https://requests.readthedocs.io/>
- <https://lxml.de/>
- <https://pyinstaller.org/>

For the exact corresponding-source and license bundle for a shipped version, email [support@sowensstudios.com](mailto:support@sowensstudios.com) with the app version and build number.

When enabled, Open Food Facts database records are available under the Open Database License (ODbL), individual database contents under the Database Contents License, and product images under the Creative Commons Attribution-ShareAlike terms specified by Open Food Facts. OpenStreetMap data is available under ODbL and must be attributed to OpenStreetMap contributors. See <https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/> and <https://www.openstreetmap.org/copyright>.

Last reviewed: August 25, 2026.
