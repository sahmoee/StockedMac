#!/usr/bin/env python3
"""
harvest-recipes.py — Batch recipe URL harvester for Stocked Mac.

Reads source definitions from default-sources.json (auto-located relative to
this script), fetches each source's sitemaps, filters the results down to URLs
that match the source's recipeURLPatterns, and writes them to a plain-text
file suitable for pasting into Stocked Mac's import box.

Features
--------
- Loads every priority-ordered source defined in default-sources.json automatically.
- Resolves sitemap indexes recursively (sitemap index → child sitemaps → URLs).
- Filters by recipeURLPatterns; excludes by excludedURLPatterns.
- Respects minimumDelaySeconds between requests.
- Graceful Ctrl-C: saves a checkpoint on interrupt so the next run resumes.
- Checkpoint resume: already-harvested sources are skipped on restart.
- Per-source daily-request-limit guard (no more than N HTTP requests per run).
- Gzip sitemap support and browser-compatible request headers.
- Automatically quarantines sources returning 401/402/403/429/451 in a local
  harvest-source-health.json file, without rewriting the shipped source catalog.
- Dry-run mode: prints what would be fetched without making any network calls.

Usage
-----
    # Harvest all enabled sources
    python3 harvest-recipes.py

    # Harvest specific sources by id
    python3 harvest-recipes.py --sources allrecipes seriouseats

    # List available sources and exit
    python3 harvest-recipes.py --list

    # Resume from a previous checkpoint
    python3 harvest-recipes.py --resume

    # Dry run (no network calls, no output files written)
    python3 harvest-recipes.py --dry-run

    # Custom output file
    python3 harvest-recipes.py --output ~/Desktop/recipe-urls.txt

    # Limit total URLs collected per source
    python3 harvest-recipes.py --limit 200

    # Show verbose progress
    python3 harvest-recipes.py --verbose
"""

import argparse
import gzip
import json
import os
import sys
import time
import signal
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from pathlib import Path
from datetime import datetime

# ---------------------------------------------------------------------------
# Locate project files relative to this script
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
SOURCES_FILE = REPO_ROOT / "default-sources.json"
DEFAULT_OUTPUT = REPO_ROOT / "harvested-urls.txt"
CHECKPOINT_FILE = REPO_ROOT / "harvest-checkpoint.json"
HEALTH_FILE = REPO_ROOT / "harvest-source-health.json"

# ---------------------------------------------------------------------------
# XML namespace helpers for sitemap parsing
# ---------------------------------------------------------------------------

SITEMAP_NS = {
    "sm": "http://www.sitemaps.org/schemas/sitemap/0.9",
    "image": "http://www.google.com/schemas/sitemap-image/1.1",
    "news": "http://www.google.com/schemas/sitemap-news/0.9",
}

USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) "
    "Stocked/1.0 +https://stocked.app/bot"
)

# ---------------------------------------------------------------------------
# Interrupt handler — set when Ctrl-C is pressed
# ---------------------------------------------------------------------------

_interrupted = False


def _handle_sigint(sig, frame):
    global _interrupted
    if not _interrupted:
        print("\n[!] Interrupt received — finishing current source then saving checkpoint …", flush=True)
        _interrupted = True


signal.signal(signal.SIGINT, _handle_sigint)


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _fetch(url: str, timeout: int = 20) -> bytes:
    """Download *url* and return the raw bytes. Raises urllib.error.URLError on failure."""
    req = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/xml,text/xml,text/html;q=0.9,*/*;q=0.1",
        "Accept-Encoding": "gzip",
        "Accept-Language": "en-US,en;q=0.9",
    })
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read()
        if resp.headers.get("Content-Encoding", "").lower() == "gzip" or data[:2] == b"\x1f\x8b":
            return gzip.decompress(data)
        return data


def _fetch_xml(url: str, timeout: int = 20) -> ET.Element:
    """Fetch *url* and parse as XML. Raises ValueError on parse errors."""
    data = _fetch(url, timeout=timeout)
    try:
        return ET.fromstring(data)
    except ET.ParseError as exc:
        raise ValueError(f"XML parse error for {url}: {exc}") from exc


# ---------------------------------------------------------------------------
# Sitemap parsing
# ---------------------------------------------------------------------------

def _tag(element: ET.Element) -> str:
    """Return the local tag name, stripping any namespace."""
    tag = element.tag
    if "}" in tag:
        return tag.split("}", 1)[1]
    return tag


def _is_sitemap_index(root: ET.Element) -> bool:
    return _tag(root) == "sitemapindex"


def _extract_locs(root: ET.Element) -> list:
    """Return all <loc> text values from a sitemap or sitemap index element."""
    locs = []
    for child in root:
        for grandchild in child:
            if _tag(grandchild) == "loc" and grandchild.text:
                locs.append(grandchild.text.strip())
    return locs


def harvest_sitemap(
    sitemap_url: str,
    recipe_patterns: list,
    excluded_patterns: list,
    delay: float,
    request_budget: list,  # [remaining] — mutated in-place
    limit: int,
    verbose: bool,
    dry_run: bool,
) -> list:
    """
    Recursively walk a sitemap or sitemap index and return matching recipe URLs.

    *request_budget* is a single-element list so this function can decrement
    the caller's counter across recursion without returning it.
    """
    if request_budget[0] <= 0:
        return []

    if dry_run:
        print(f"  [dry-run] would fetch sitemap: {sitemap_url}")
        return []

    if verbose:
        print(f"  Fetching sitemap: {sitemap_url}", flush=True)

    request_budget[0] -= 1
    try:
        root = _fetch_xml(sitemap_url)
    except urllib.error.HTTPError as exc:
        if exc.code in {401, 402, 403, 429, 451}:
            raise SourceAccessLimited(sitemap_url, exc.code) from exc
        print(f"  [warn] Could not fetch {sitemap_url}: HTTP {exc.code}", file=sys.stderr)
        return []
    except (urllib.error.URLError, ValueError, OSError) as exc:
        print(f"  [warn] Could not fetch {sitemap_url}: {exc}", file=sys.stderr)
        return []

    if delay > 0:
        time.sleep(delay)

    urls: list = []

    if _is_sitemap_index(root):
        child_sitemaps = _extract_locs(root)
        if verbose:
            print(f"  Sitemap index with {len(child_sitemaps)} child sitemaps", flush=True)
        for child_url in child_sitemaps:
            if _interrupted or request_budget[0] <= 0:
                break
            urls.extend(harvest_sitemap(
                child_url,
                recipe_patterns,
                excluded_patterns,
                delay,
                request_budget,
                limit,
                verbose,
                dry_run,
            ))
            if len(urls) >= limit:
                break
    else:
        # Regular sitemap
        all_locs = _extract_locs(root)
        for loc in all_locs:
            if len(urls) >= limit:
                break
            if not _matches(loc, recipe_patterns, excluded_patterns):
                continue
            urls.append(loc)

    return urls


def _matches(url: str, include_patterns: list, exclude_patterns: list) -> bool:
    """
    Return True if *url* should be kept.

    If *include_patterns* is empty every URL passes the include check.
    The URL is then rejected if it matches any exclude pattern.
    """
    if include_patterns:
        if not any(p in url for p in include_patterns):
            return False
    if any(p in url for p in exclude_patterns):
        return False
    return True


class SourceAccessLimited(RuntimeError):
    """The site explicitly refused or limited automated recipe access."""

    def __init__(self, url: str, status: int):
        super().__init__(f"HTTP {status} from {url}")
        self.url = url
        self.status = status


# ---------------------------------------------------------------------------
# Checkpoint helpers
# ---------------------------------------------------------------------------

def load_checkpoint() -> dict:
    if CHECKPOINT_FILE.exists():
        try:
            with open(CHECKPOINT_FILE) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {"completed": [], "urls": {}}


def save_checkpoint(checkpoint: dict) -> None:
    try:
        with open(CHECKPOINT_FILE, "w") as f:
            json.dump(checkpoint, f, indent=2)
        print(f"[✓] Checkpoint saved to {CHECKPOINT_FILE}", flush=True)
    except OSError as exc:
        print(f"[warn] Could not save checkpoint: {exc}", file=sys.stderr)


def clear_checkpoint() -> None:
    if CHECKPOINT_FILE.exists():
        CHECKPOINT_FILE.unlink()


# ---------------------------------------------------------------------------
# Source loading
# ---------------------------------------------------------------------------

def load_sources(sources_file: Path) -> list:
    if not sources_file.exists():
        print(f"Error: sources file not found: {sources_file}", file=sys.stderr)
        sys.exit(1)
    with open(sources_file) as f:
        return json.load(f)


def filter_sources(sources: list, ids: list, only_enabled: bool) -> list:
    if ids:
        wanted = set(ids)
        sources = [s for s in sources if s.get("id") in wanted]
        missing = wanted - {s.get("id") for s in sources}
        if missing:
            print(f"[warn] Unknown source ids: {', '.join(sorted(missing))}", file=sys.stderr)
    if only_enabled:
        sources = [s for s in sources if s.get("enabled", True) and s.get("discoveryEnabled", True)]
    return sources


# ---------------------------------------------------------------------------
# Harvest one source
# ---------------------------------------------------------------------------

def harvest_source(source: dict, limit: int, verbose: bool, dry_run: bool) -> list:
    source_id = source.get("id", "?")
    name = source.get("name", source_id)
    sitemap_urls = source.get("sitemapURLs", [])
    recipe_patterns = source.get("recipeURLPatterns", [])
    excluded_patterns = source.get("excludedURLPatterns", [])
    delay = float(source.get("minimumDelaySeconds", 1))
    daily_limit = int(source.get("dailyRequestLimit", 100))

    if not sitemap_urls:
        print(f"  [{source_id}] No sitemapURLs defined — skipping.", file=sys.stderr)
        return []

    print(f"\n→ {name} ({source_id})", flush=True)

    all_urls: list = []
    request_budget = [daily_limit]

    for sitemap_url in sitemap_urls:
        if _interrupted or request_budget[0] <= 0:
            break
        try:
            found = harvest_sitemap(
                sitemap_url,
                recipe_patterns,
                excluded_patterns,
                delay,
                request_budget,
                limit,
                verbose,
                dry_run,
            )
        except SourceAccessLimited as exc:
            source["discoveryEnabled"] = False
            source["health"] = "paused" if exc.status == 429 else "blocked"
            source["notes"] = (source.get("notes", "") +
                f"\nAutomatic discovery disabled by harvest-recipes.py: HTTP {exc.status}.").strip()
            print(f"  [limited] HTTP {exc.status}; removing {name} from future automatic harvests.", file=sys.stderr)
            break
        all_urls.extend(found)
        if verbose:
            print(f"  +{len(found)} URLs (total {len(all_urls)})", flush=True)
        if len(all_urls) >= limit:
            break

    # Deduplicate while preserving order
    seen: set = set()
    deduped: list = []
    for url in all_urls:
        if url not in seen:
            seen.add(url)
            deduped.append(url)

    print(f"  Found {len(deduped)} recipe URLs", flush=True)
    return deduped[:limit]


def load_source_health(sources: list) -> None:
    """Apply local access-limit decisions without editing the shipped catalog."""
    if not HEALTH_FILE.exists():
        return
    try:
        states = json.loads(HEALTH_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return
    for source in sources:
        if source.get("id") in states:
            source.update(states[source["id"]])


def persist_source_health(sources: list) -> None:
    states = {
        source.get("id"): {
            "discoveryEnabled": source.get("discoveryEnabled", True),
            "health": source.get("health", "unknown"),
            "notes": source.get("notes"),
        }
        for source in sources
        if source.get("id") and source.get("health") in {"paused", "blocked"}
    }
    with open(HEALTH_FILE, "w") as handle:
        json.dump(states, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def write_output(all_urls: dict, output_path: Path, append: bool) -> None:
    """Write a flat newline-separated list of all URLs to *output_path*."""
    mode = "a" if append else "w"
    with open(output_path, mode) as f:
        if not append:
            f.write(f"# Harvested by harvest-recipes.py — {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
            f.write("# Paste these URLs into Stocked Mac's import box.\n\n")
        for source_id, urls in all_urls.items():
            if urls:
                f.write(f"## {source_id}\n")
                for url in urls:
                    f.write(url + "\n")
                f.write("\n")
    total = sum(len(v) for v in all_urls.values())
    print(f"\n[✓] Wrote {total} URLs to {output_path}")


def print_flat(all_urls: dict) -> None:
    """Print just the URLs to stdout — useful for piping."""
    for urls in all_urls.values():
        for url in urls:
            print(url)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--sources", "-s",
        nargs="+",
        metavar="ID",
        help="Harvest only these source IDs (default: all enabled sources).",
    )
    p.add_argument(
        "--list", "-l",
        action="store_true",
        help="List available sources and exit.",
    )
    p.add_argument(
        "--output", "-o",
        type=Path,
        default=DEFAULT_OUTPUT,
        metavar="FILE",
        help=f"Output file (default: {DEFAULT_OUTPUT.name}).",
    )
    p.add_argument(
        "--stdout",
        action="store_true",
        help="Print URLs to stdout instead of writing a file.",
    )
    p.add_argument(
        "--limit", "-n",
        type=int,
        default=500,
        metavar="N",
        help="Maximum URLs to collect per source (default: 500).",
    )
    p.add_argument(
        "--resume",
        action="store_true",
        help="Resume from a previous checkpoint (skip already-harvested sources).",
    )
    p.add_argument(
        "--reset",
        action="store_true",
        help="Delete the checkpoint file and start fresh.",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be fetched without making network calls.",
    )
    p.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed progress.",
    )
    p.add_argument(
        "--all",
        action="store_true",
        help="Include disabled sources (default: skip disabled).",
    )
    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    # Load sources
    sources = load_sources(SOURCES_FILE)
    load_source_health(sources)

    if args.list:
        print(f"{'ID':<30} {'Name':<35} {'Enabled':<8} {'Sitemaps'}")
        print("-" * 90)
        for s in sources:
            enabled = "yes" if s.get("enabled", True) and s.get("discoveryEnabled", True) else "no"
            sitemap_count = len(s.get("sitemapURLs", []))
            print(f"{s.get('id','?'):<30} {s.get('name','?'):<35} {enabled:<8} {sitemap_count}")
        print(f"\nTotal: {len(sources)} sources")
        return 0

    if args.reset:
        clear_checkpoint()
        print("[✓] Checkpoint cleared.")

    # Handle checkpoint resume
    checkpoint = load_checkpoint() if args.resume else {"completed": [], "urls": {}}
    already_done = set(checkpoint.get("completed", []))
    all_collected: dict = dict(checkpoint.get("urls", {}))

    # Filter to requested sources
    only_enabled = not args.all
    work_sources = filter_sources(sources, args.sources, only_enabled)

    if args.resume:
        work_sources = [s for s in work_sources if s.get("id") not in already_done]
        if already_done:
            print(f"[resume] Skipping {len(already_done)} already-completed source(s): {', '.join(sorted(already_done))}")

    if not work_sources:
        print("No sources to harvest. Use --list to see available sources.")
        return 0

    print(f"Harvesting {len(work_sources)} source(s). Ctrl-C to pause and save checkpoint.\n")

    for source in work_sources:
        if _interrupted:
            break
        source_id = source.get("id", "?")
        urls = harvest_source(source, args.limit, args.verbose, args.dry_run)
        all_collected[source_id] = urls
        already_done.add(source_id)

    if any(not source.get("discoveryEnabled", True) and source.get("health") in {"paused", "blocked"}
           for source in work_sources):
        persist_source_health(sources)
        print(f"[✓] Saved access-limited source removals to {HEALTH_FILE.name}.")

    # Save checkpoint if interrupted or explicitly resuming
    if _interrupted or args.resume:
        save_checkpoint({"completed": list(already_done), "urls": all_collected})

    if not all_collected:
        print("No URLs collected.")
        return 0

    total = sum(len(v) for v in all_collected.values())

    if args.dry_run:
        print(f"\n[dry-run] Would have written {total} URLs.")
        return 0

    if args.stdout:
        print_flat(all_collected)
    else:
        write_output(all_collected, args.output, append=False)

    if _interrupted:
        print("\n[!] Run again with --resume to continue from where you left off.")
        return 1

    # Clean up checkpoint on success
    if not args.resume:
        pass  # keep any existing checkpoint untouched
    else:
        clear_checkpoint()
        print("[✓] All sources complete — checkpoint cleared.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
