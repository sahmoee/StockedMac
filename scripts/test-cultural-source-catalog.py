#!/usr/bin/env python3
"""Regression checks for Stocked's cultural recipe source expansion."""

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLED = ROOT / "StockedMac" / "default-sources.json"
EDITABLE = ROOT / "default-sources.json"
SWIFT = ROOT / "StockedMac" / "Harvest" / "DefaultSourceCatalog.swift"
EXPECTED_GROUPS = {"Black Food Culture": 10, "African American & Soul Food": 10, "Southern": 10}


def main() -> None:
    catalog = json.loads(BUNDLED.read_text())
    assert catalog == json.loads(EDITABLE.read_text()), "Bundled and scanner catalogs differ"
    assert len(catalog) == 280, f"Expected 280 sources, found {len(catalog)}"
    ids = [source["id"] for source in catalog]
    assert len(ids) == len(set(ids)), "Duplicate source IDs found"
    requested = [source for source in catalog if any(group in source["tags"] for group in EXPECTED_GROUPS) and "September 2026 Stocked source audit" in source.get("notes", "")]
    counts = Counter(group for source in requested for group in EXPECTED_GROUPS if group in source["tags"])
    assert counts == Counter(EXPECTED_GROUPS), f"Unexpected group counts: {counts}"
    for source in requested:
        assert source["enabled"] and source["discoveryEnabled"]
        assert source["discoveryMode"] == "sitemapOnly" and source["parserMode"] == "nativeFirst"
        assert source["robotsRequired"] and source["maximumConcurrency"] == 1
        assert source["sitemapURLs"] and all(url.startswith("https://") for url in source["sitemapURLs"])
    match = re.search(r'#"""\n([\s\S]*?)\n"""#', SWIFT.read_text())
    assert match and json.loads(match.group(1)) == catalog, "Embedded Swift catalog differs"
    print("Verified 280 synchronized sources and three 10-site cultural source groups.")


if __name__ == "__main__":
    main()
