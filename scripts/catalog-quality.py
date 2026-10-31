#!/usr/bin/env python3
"""Normalize and audit bulk grocery catalog exports for StockedMac.

Accepts a JSON array, JSON Lines, or an API envelope containing ``products``,
``locations``, ``library``, or ``queue``. The output is deterministic JSON that
can be diffed, archived, or fed to future import tooling. It uses only Python's
standard library, never reads app secrets, and never makes network requests.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


EXCLUDED = (
    "pet food", "dog food", "cat food", "beauty", "cosmetic", "makeup",
    "skin care", "hair care", "shampoo", "deodorant", "fragrance",
    "toy", "electronics", "automotive", "clothing", "pharmacy",
)
AISLES = (
    ("Produce", ("fruit", "vegetable", "produce", "salad", "herb", "fresh")),
    ("Bakery", ("bread", "bakery", "tortilla", "bun", "cake")),
    ("Dairy & Eggs", ("milk", "cheese", "yogurt", "butter", "egg", "dairy")),
    ("Meat & Seafood", ("meat", "beef", "pork", "chicken", "turkey", "fish", "seafood")),
    ("Frozen", ("frozen", "ice cream")),
    ("Canned & Jarred", ("canned", "preserved", "sauce", "pickle", "jar")),
    ("Pasta, Rice & Grains", ("pasta", "rice", "grain", "cereal", "noodle")),
    ("Baking", ("baking", "flour", "sugar", "yeast", "chocolate")),
    ("Snacks", ("snack", "chip", "cracker", "popcorn", "candy")),
    ("Beverages", ("beverage", "drink", "water", "coffee", "tea", "juice", "soda")),
    ("Condiments & Spices", ("condiment", "spice", "seasoning", "oil", "vinegar")),
    ("Household", ("household", "cleaner", "paper", "laundry", "trash")),
)


def clean_text(value: Any, limit: int = 500) -> str | None:
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    return text[:limit] or None


def clean_upc(value: Any) -> str | None:
    digits = re.sub(r"\D", "", str(value or ""))
    return digits if 8 <= len(digits) <= 14 else None


def clean_name(value: Any) -> str | None:
    name = clean_text(value, 300)
    if not name:
        return None
    # Search APIs commonly append internal IDs to display names. Keep meaningful
    # quantities/years, but remove a final 5+ digit token with no unit context.
    return re.sub(r"\s+\d{5,}$", "", name).strip() or None


def number(value: Any) -> float | None:
    if isinstance(value, dict):
        value = value.get("amount", value.get("value", value.get("current")))
    match = re.search(r"-?\d+(?:\.\d+)?", str(value or ""))
    return float(match.group()) if match else None


def flattened_items(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if not isinstance(payload, dict):
        return []
    for key in ("products", "locations", "library", "queue", "items", "results", "data"):
        value = payload.get(key)
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
        if isinstance(value, dict):
            nested = flattened_items(value)
            if nested:
                return nested
    return [payload]


def image_candidates(item: dict[str, Any]) -> Iterable[str]:
    for key in ("imageURL", "image_url", "image", "imageUrl", "thumbnail"):
        value = clean_text(item.get(key), 2_000)
        if value:
            yield value
    for image in item.get("images") or []:
        if isinstance(image, str):
            yield image
        elif isinstance(image, dict):
            for size in image.get("sizes") or []:
                if isinstance(size, dict) and clean_text(size.get("url"), 2_000):
                    yield clean_text(size["url"], 2_000) or ""


def best_image(item: dict[str, Any]) -> str | None:
    candidates = list(dict.fromkeys(image_candidates(item)))
    if not candidates:
        return None
    def score(url: str) -> tuple[int, int]:
        lowered = url.lower()
        quality = 4 if any(word in lowered for word in ("xlarge", "original", ".full.")) else 0
        quality += 2 if "large" in lowered else 0
        quality -= 2 if any(word in lowered for word in ("thumb", "small", ".200.", ".400.")) else 0
        return quality, len(url)
    return max(candidates, key=score)


def aisle_for(name: str, categories: list[str], item: dict[str, Any]) -> str:
    locations = item.get("aisleLocations") or []
    if locations and isinstance(locations[0], dict):
        aisle = locations[0]
        parts = [f"Aisle {aisle.get('number')}" if aisle.get("number") else None,
                 clean_text(aisle.get("description")),
                 f"Side {aisle.get('side')}" if aisle.get("side") else None,
                 f"Shelf {aisle.get('shelfNumber')}" if aisle.get("shelfNumber") else None]
        exact = " · ".join(part for part in parts if part)
        if exact:
            return exact
    value = " ".join([name, *categories]).lower()
    for aisle, words in AISLES:
        if any(word in value for word in words):
            return aisle
    return "Pantry"


def normalize(item: dict[str, Any]) -> dict[str, Any] | None:
    address = item.get("address") if isinstance(item.get("address"), dict) else {}
    is_location = bool(item.get("locationId") and address)
    if is_location:
        name = clean_name(item.get("name"))
        if not name:
            return None
        address_text = " · ".join(filter(None, (
            clean_text(address.get("line1") or address.get("addressLine1")),
            clean_text(address.get("city")), clean_text(address.get("state")),
            clean_text(address.get("zipCode")),
        )))
        return {
            "kind": "Store", "name": name, "store": name,
            "address": address_text or None,
            "externalID": clean_text(item.get("locationId"), 80),
            "latitude": number(item.get("latitude")), "longitude": number(item.get("longitude")),
            "source": clean_text(item.get("provider")) or "bulk-import",
        }

    name = clean_name(item.get("name") or item.get("description") or item.get("title")
                      or item.get("product_name"))
    if not name:
        return None
    categories_raw = item.get("categories") or item.get("category") or []
    if isinstance(categories_raw, str):
        categories = [part.strip() for part in categories_raw.split(",") if part.strip()]
    else:
        categories = [clean_text(value, 180) for value in categories_raw if clean_text(value, 180)]
    searchable = " ".join([name, *categories]).lower()
    if any(term in searchable for term in EXCLUDED):
        return None
    price = item.get("price") if isinstance(item.get("price"), dict) else {}
    return {
        "kind": "Product", "name": name,
        "brand": clean_text(item.get("brand") or item.get("brand_name") or item.get("manufacturer"), 180),
        "category": categories[0] if categories else None,
        "categories": categories,
        "aisle": aisle_for(name, categories, item),
        "store": clean_text(item.get("store"), 180),
        "barcode": clean_upc(item.get("upc") or item.get("barcode") or item.get("gtin")),
        "externalID": clean_text(item.get("productId") or item.get("id") or item.get("sku"), 100),
        "retailerLocationID": clean_text(item.get("locationId"), 80),
        "regularPrice": number(item.get("regularPrice", price.get("regular"))),
        "promotionalPrice": number(item.get("promoPrice", price.get("promo"))),
        "inventoryLevel": clean_text(item.get("inventoryLevel") or (item.get("inventory") or {}).get("stockLevel"), 80),
        "imageURL": best_image(item),
        "sourceURL": clean_text(item.get("productURL") or item.get("url"), 2_000),
        "source": clean_text(item.get("provider")) or "bulk-import",
    }


def richness(item: dict[str, Any]) -> int:
    return sum(value not in (None, "", [], {}) for value in item.values())


def identity(item: dict[str, Any]) -> str:
    if item.get("barcode"):
        return f"upc:{item['barcode']}"
    return "|".join(str(item.get(key) or "").casefold() for key in ("kind", "name", "brand", "store"))


def load(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8")
    try:
        return flattened_items(json.loads(text))
    except json.JSONDecodeError:
        return [json.loads(line) for line in text.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--require-product-images", action="store_true",
                        help="drop product records without a usable image URL")
    args = parser.parse_args()

    raw = load(args.input)
    rejected = 0
    missing_images = 0
    unique: dict[str, dict[str, Any]] = {}
    for source in raw:
        record = normalize(source)
        if not record:
            rejected += 1
            continue
        if record["kind"] == "Product" and not record.get("imageURL"):
            missing_images += 1
            if args.require_product_images:
                rejected += 1
                continue
        key = identity(record)
        previous = unique.get(key)
        if previous is None or richness(record) > richness(previous):
            unique[key] = record

    output = sorted(unique.values(), key=lambda item: (item["kind"], item["name"].casefold()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    report = {
        "read": len(raw), "written": len(output), "rejected": rejected,
        "duplicatesRemoved": len(raw) - rejected - len(output), "productsMissingImages": missing_images,
        "output": str(args.output),
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
