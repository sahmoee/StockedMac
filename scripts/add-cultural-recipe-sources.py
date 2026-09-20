#!/usr/bin/env python3
"""Add the audited Black, African American/soul-food, and Southern source sets."""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
BUNDLED_PATH = ROOT / "StockedMac" / "default-sources.json"
ROOT_PATH = ROOT / "default-sources.json"
SWIFT_PATH = ROOT / "StockedMac" / "Harvest" / "DefaultSourceCatalog.swift"

# id, name, base URL, sitemap URL, catalog group
SOURCES = [
    ("black-peoples-recipes", "Black People's Recipes", "https://blackpeoplesrecipes.com", "https://blackpeoplesrecipes.com/sitemap_index.xml", "Black Food Culture"),
    ("jessica-in-the-kitchen", "Jessica in the Kitchen", "https://jessicainthekitchen.com", "https://jessicainthekitchen.com/sitemap_index.xml", "Black Food Culture"),
    ("divas-can-cook", "Divas Can Cook", "https://divascancook.com", "https://divascancook.com/wp-sitemap.xml", "Black Food Culture"),
    ("i-heart-recipes", "I Heart Recipes", "https://iheartrecipes.com", "https://iheartrecipes.com/sitemap_index.xml", "Black Food Culture"),
    ("my-forking-life", "My Forking Life", "https://www.myforkinglife.com", "https://www.myforkinglife.com/sitemap_index.xml", "Black Food Culture"),
    ("butter-be-ready", "Butter Be Ready", "https://www.butterbeready.com", "https://www.butterbeready.com/sitemap_index.xml", "Black Food Culture"),
    ("britney-breaks-bread", "Britney Breaks Bread", "https://britneybreaksbread.com", "https://britneybreaksbread.com/sitemap_index.xml", "Black Food Culture"),
    ("the-seasoned-skillet", "The Seasoned Skillet", "https://seasonedskilletblog.com", "https://seasonedskilletblog.com/sitemap_index.xml", "Black Food Culture"),
    ("sense-and-edibility", "Sense & Edibility", "https://senseandedibility.com", "https://senseandedibility.com/sitemap_index.xml", "Black Food Culture"),
    ("meiko-and-the-dish", "Meiko and the Dish", "https://meikoandthedish.com", "https://meikoandthedish.com/sitemap_index.xml", "Black Food Culture"),
    ("food-fidelity", "Food Fidelity", "https://www.foodfidelity.com", "https://www.foodfidelity.com/sitemap_index.xml", "African American & Soul Food"),
    ("on-tys-plate", "On Ty's Plate", "https://www.ontysplate.com", "https://www.ontysplate.com/sitemap_index.xml", "African American & Soul Food"),
    ("dude-that-cookz", "Dude That Cookz", "https://dudethatcookz.com", "https://dudethatcookz.com/sitemap_index.xml", "African American & Soul Food"),
    ("kenneth-temple", "Kenneth Temple", "https://kennethtemple.com", "https://kennethtemple.com/sitemap_index.xml", "African American & Soul Food"),
    ("sweet-tea-and-thyme", "Sweet Tea + Thyme", "https://www.sweetteaandthyme.com", "https://www.sweetteaandthyme.com/sitemap_index.xml", "African American & Soul Food"),
    ("dash-of-jazz", "Dash of Jazz", "https://www.dashofjazz.com", "https://dashofjazz.com/sitemap_index.xml", "African American & Soul Food"),
    ("chenee-today", "Chenée Today", "https://cheneetoday.com", "https://cheneetoday.com/sitemap_index.xml", "African American & Soul Food"),
    ("razzle-dazzle-life", "Razzle Dazzle Life", "https://www.razzledazzlelife.com", "https://www.razzledazzlelife.com/sitemap_index.xml", "African American & Soul Food"),
    ("coop-can-cook", "Coop Can Cook", "https://coopcancook.com", "https://coopcancook.com/sitemap_index.xml", "African American & Soul Food"),
    ("stay-snatched", "Stay Snatched", "https://www.staysnatched.com", "https://www.staysnatched.com/sitemap_index.xml", "African American & Soul Food"),
    ("spicy-southern-kitchen", "Spicy Southern Kitchen", "https://spicysouthernkitchen.com", "https://spicysouthernkitchen.com/sitemap_index.xml", "Southern"),
    ("ranch-style-kitchen", "Ranch Style Kitchen", "https://www.ranchstylekitchen.com", "https://www.ranchstylekitchen.com/sitemap_index.xml", "Southern"),
    ("southern-bite", "Southern Bite", "https://southernbite.com", "https://southernbite.com/sitemap_index.xml", "Southern"),
    ("deep-south-dish", "Deep South Dish", "https://www.deepsouthdish.com", "https://www.deepsouthdish.com/sitemap.xml", "Southern"),
    ("julias-simply-southern", "Julia's Simply Southern", "https://juliassimplysouthern.com", "https://juliassimplysouthern.com/sitemap_index.xml", "Southern"),
    ("quiche-my-grits", "Quiche My Grits", "https://quichemygrits.com", "https://quichemygrits.com/sitemap_index.xml", "Southern"),
    ("biscuits-and-burlap", "Biscuits & Burlap", "https://www.biscuitsandburlap.com", "https://biscuitsandburlap.com/sitemap_index.xml", "Southern"),
    ("lanas-cooking", "Lana's Cooking", "https://www.lanascooking.com", "https://lanascooking.com/sitemap_index.xml", "Southern"),
    ("southern-discourse", "Southern Discourse", "https://southerndiscourse.com", "https://southerndiscourse.com/sitemap_index.xml", "Southern"),
    ("south-your-mouth", "South Your Mouth", "https://www.southyourmouth.com", "https://www.southyourmouth.com/sitemap.xml", "Southern"),
]


def normalized_domain(value: str) -> str:
    host = urlparse(value if "://" in value else f"https://{value}").hostname or value
    return host.lower().removeprefix("www.")


def profile(source_id: str, name: str, base_url: str, sitemap_url: str, group: str) -> dict:
    host = urlparse(base_url).hostname or ""
    tags = ["English", group, "Structured Data"]
    if group == "African American & Soul Food":
        tags.extend(["African American", "Soul Food"])
    elif group == "Southern":
        tags.extend(["American", "Comfort Food"])
    return {
        "id": source_id,
        "name": name,
        "domains": sorted({host, normalized_domain(host)}),
        "baseURL": base_url,
        "enabled": True,
        "discoveryEnabled": True,
        "discoveryMode": "sitemapOnly",
        "parserMode": "nativeFirst",
        "minimumDelaySeconds": 3,
        "maximumConcurrency": 1,
        "dailyRequestLimit": 100,
        "robotsRequired": True,
        "imageDownloadEnabled": True,
        "sitemapURLs": [sitemap_url],
        "recipeURLPatterns": [],
        "excludedURLPatterns": ["/author/", "/page/", "/shop/", "/video/"],
        "tags": tags,
        "notes": f"{group} recipe publisher; HTTPS homepage and XML sitemap verified in the September 2026 Stocked source audit.",
        "health": "unknown",
    }


def validate(catalog: list[dict]) -> None:
    ids = [source["id"] for source in catalog]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate source IDs found")
    expected = {source[0] for source in SOURCES}
    if expected - set(ids):
        raise ValueError(f"Missing requested source IDs: {sorted(expected - set(ids))}")


def main() -> None:
    catalog = json.loads(BUNDLED_PATH.read_text())
    ids = {source["id"] for source in catalog}
    domains = {normalized_domain(domain) for source in catalog for domain in source["domains"]}
    additions = []
    for row in SOURCES:
        item = profile(*row)
        domain = normalized_domain(item["baseURL"])
        if item["id"] in ids:
            continue
        if domain in domains:
            raise ValueError(f"Refusing duplicate source {item['id']} ({domain})")
        ids.add(item["id"])
        domains.add(domain)
        additions.append(item)
    catalog.extend(additions)
    validate(catalog)
    if len(catalog) != 280:
        raise ValueError(f"Expected 280 sources after additions, found {len(catalog)}")

    pretty = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    BUNDLED_PATH.write_text(pretty)
    ROOT_PATH.write_text(pretty)
    swift = SWIFT_PATH.read_text()
    encoded = json.dumps(catalog, separators=(",", ":"), ensure_ascii=False)
    swift, count = re.subn(r'(#"""\n)[\s\S]*?(\n"""#)', rf'\g<1>{encoded}\g<2>', swift, count=1)
    if count != 1:
        raise ValueError("Could not replace embedded Swift source catalog")
    SWIFT_PATH.write_text(swift)
    print(f"Added {len(additions)} new sources; synchronized {len(catalog)} total sources.")


if __name__ == "__main__":
    main()
