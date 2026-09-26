#!/usr/bin/env python3
"""Audit and add 100 English-language global recipe sources to both catalogs."""

from __future__ import annotations

import json
import re
import socket
import ssl
import sys
import urllib.parse
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JSON_PATH = ROOT / "StockedMac" / "default-sources.json"
SWIFT_PATH = ROOT / "StockedMac" / "Harvest" / "DefaultSourceCatalog.swift"

# name, domain, cuisine/specialty tags. All candidates publish primarily in English.
CANDIDATES = [
    ("Swasthi's Recipes", "indianhealthyrecipes.com", ["Indian", "South Asian"]),
    ("Dassana's Veg Recipes", "vegrecipesofindia.com", ["Indian", "Vegetarian"]),
    ("My Heart Beets", "myheartbeets.com", ["Indian", "Gluten-free"]),
    ("Ministry of Curry", "ministryofcurry.com", ["Indian", "Instant Pot"]),
    ("Piping Pot Curry", "pipingpotcurry.com", ["Indian", "Instant Pot"]),
    ("Cook With Manali", "cookwithmanali.com", ["Indian", "Vegetarian"]),
    ("Cubes N Juliennes", "cubesnjuliennes.com", ["Indian", "Everyday"]),
    ("WhiskAffair", "whiskaffair.com", ["Indian", "Global"]),
    ("Hebbars Kitchen", "hebbarskitchen.com", ["Indian", "Vegetarian"]),
    ("Spice Up The Curry", "spiceupthecurry.com", ["Indian", "Vegetarian"]),
    ("Tea for Turmeric", "teaforturmeric.com", ["Pakistani", "South Asian"]),
    ("Pakistan Eats", "pakistaneats.com", ["Pakistani", "South Asian"]),
    ("Fatima Cooks", "fatimacooks.net", ["Pakistani", "South Asian"]),
    ("Recipe52", "recipe52.com", ["Pakistani", "South Asian"]),
    ("Chili to Choc", "chilitochoc.com", ["Pakistani", "Global"]),
    ("Hungry Paprikas", "hungrypaprikas.com", ["Middle Eastern", "Arab"]),
    ("Amira's Pantry", "amiraspantry.com", ["Middle Eastern", "Egyptian"]),
    ("FalasteeniFoodie", "falasteenifoodie.com", ["Palestinian", "Middle Eastern"]),
    ("Silk Road Recipes", "silkroadrecipes.com", ["Asian", "Middle Eastern"]),
    ("Maureen Abood", "maureenabood.com", ["Lebanese", "Middle Eastern"]),
    ("The Matbakh", "thematbakh.com", ["Middle Eastern", "Mediterranean"]),
    ("Cardamom and Tea", "cardamomandtea.com", ["Middle Eastern", "Assyrian"]),
    ("Unicorns in the Kitchen", "unicornsinthekitchen.com", ["Persian", "Mediterranean"]),
    ("Persian Mama", "persianmama.com", ["Persian", "Iranian"]),
    ("Turkish Food Travel", "turkishfoodtravel.com", ["Turkish", "Mediterranean"]),
    ("Give Recipe", "giverecipe.com", ["Turkish", "Mediterranean"]),
    ("Ozlem's Turkish Table", "ozlemsturkishtable.com", ["Turkish", "Mediterranean"]),
    ("Red House Spice", "redhousespice.com", ["Chinese", "Asian"]),
    ("China Sichuan Food", "chinasichuanfood.com", ["Chinese", "Sichuan"]),
    ("Made With Lau", "madewithlau.com", ["Chinese", "Cantonese"]),
    ("Souped Up Recipes", "soupeduprecipes.com", ["Chinese", "Asian"]),
    ("Wok and Kin", "wokandkin.com", ["Vietnamese", "Chinese"]),
    ("Taste of Asian Food", "tasteasianfood.com", ["Asian", "Chinese"]),
    ("Christine's Recipes", "en.christinesrecipes.com", ["Chinese", "Hong Kong"]),
    ("Chopstick Chronicles", "chopstickchronicles.com", ["Japanese", "Asian"]),
    ("Sudachi", "sudachirecipes.com", ["Japanese", "Asian"]),
    ("No Recipes", "norecipes.com", ["Japanese", "Global"]),
    ("Japanese Cooking 101", "japanesecooking101.com", ["Japanese", "Asian"]),
    ("Okonomi Kitchen", "okonomikitchen.com", ["Japanese", "Vegan"]),
    ("Korean Bapsang", "koreanbapsang.com", ["Korean", "Asian"]),
    ("My Korean Kitchen", "mykoreankitchen.com", ["Korean", "Asian"]),
    ("Beyond Kimchee", "beyondkimchee.com", ["Korean", "Asian"]),
    ("Kimchimari", "kimchimari.com", ["Korean", "Asian"]),
    ("Hot Thai Kitchen", "hot-thai-kitchen.com", ["Thai", "Southeast Asian"]),
    ("Hungry Huy", "hungryhuy.com", ["Vietnamese", "Southeast Asian"]),
    ("Vicky Pham", "vickypham.com", ["Vietnamese", "Southeast Asian"]),
    ("Wok and Skillet", "wokandskillet.com", ["Southeast Asian", "Asian"]),
    ("Kawaling Pinoy", "kawalingpinoy.com", ["Filipino", "Southeast Asian"]),
    ("Panlasang Pinoy", "panlasangpinoy.com", ["Filipino", "Southeast Asian"]),
    ("Riverten Kitchen", "rivertenkitchen.com", ["Filipino", "Southeast Asian"]),
    ("Foxy Folksy", "foxyfolksy.com", ["Filipino", "Southeast Asian"]),
    ("The Burning Kitchen", "theburningkitchen.com", ["Singaporean", "Southeast Asian"]),
    ("What To Cook Today", "whattocooktoday.com", ["Indonesian", "Southeast Asian"]),
    ("Devour Asia", "devour.asia", ["Southeast Asian", "Asian"]),
    ("Low Carb Africa", "lowcarbafrica.com", ["African", "Low-carb"]),
    ("Chef Lola's Kitchen", "cheflolaskitchen.com", ["African", "Nigerian"]),
    ("Yummy Medley", "yummymedley.com", ["African", "Nigerian"]),
    ("Eat Well Abi", "eatwellabi.com", ["African", "West African"]),
    ("My Active Kitchen", "myactivekitchen.com", ["African", "Nigerian"]),
    ("K's Cuisine", "kscuisine.com", ["African", "Nigerian"]),
    ("Precious Core", "preciouscore.com", ["African", "Cameroonian"]),
    ("The Canadian African", "thecanadianafrican.com", ["African", "Ghanaian"]),
    ("Kerri-Ann's Kravings", "kerriannskravings.com", ["Caribbean", "Jamaican"]),
    ("That Girl Cooks Healthy", "thatgirlcookshealthy.com", ["Caribbean", "Gluten-free"]),
    ("Jamaican Foods and Recipes", "jamaicanfoodsandrecipes.com", ["Caribbean", "Jamaican"]),
    ("Alica's Pepperpot", "alicaspepperpot.com", ["Caribbean", "Guyanese"]),
    ("Cooking With Ria", "cookingwithria.com", ["Caribbean", "Trinidadian"]),
    ("Mexican Please", "mexicanplease.com", ["Mexican", "Latin American"]),
    ("Mexico in My Kitchen", "mexicoinmykitchen.com", ["Mexican", "Traditional"]),
    ("Muy Bueno", "muybuenoblog.com", ["Mexican", "Latin American"]),
    ("Isabel Eats", "isabeleats.com", ["Mexican", "Tex-Mex"]),
    ("Mama Maggie's Kitchen", "inmamamaggieskitchen.com", ["Mexican", "Traditional"]),
    ("La Piña en la Cocina", "pinaenlacocina.com", ["Mexican", "Traditional"]),
    ("Mexican Food Journal", "mexicanfoodjournal.com", ["Mexican", "Traditional"]),
    ("My Colombian Recipes", "mycolombianrecipes.com", ["Colombian", "Latin American"]),
    ("Laylita's Recipes", "laylita.com", ["Ecuadorian", "Latin American"]),
    ("Dominican Cooking", "dominicancooking.com", ["Dominican", "Caribbean"]),
    ("The Noshery", "thenoshery.com", ["Puerto Rican", "Caribbean"]),
    ("Brazilian Kitchen Abroad", "braziliankitchenabroad.com", ["Brazilian", "South American"]),
    ("Olivia's Cuisine", "oliviascuisine.com", ["Brazilian", "Global"]),
    ("Easy and Delish", "easyanddelish.com", ["Brazilian", "Global"]),
    ("Peru Delights", "perudelights.com", ["Peruvian", "South American"]),
    ("Kevin Is Cooking", "keviniscooking.com", ["Global", "American"]),
    ("Kitchen Sanctuary", "kitchensanctuary.com", ["British", "Everyday"]),
    ("Taming Twins", "tamingtwins.com", ["British", "Family"]),
    ("Easy Peasy Foodie", "easypeasyfoodie.com", ["British", "Quick & easy"]),
    ("Effortless Foodie", "effortlessfoodie.com", ["British", "Family"]),
    ("Flawless Food", "flawlessfood.co.uk", ["British", "Global"]),
    ("Hungry Healthy Happy", "hungryhealthyhappy.com", ["British", "Healthy"]),
    ("Charlotte's Lively Kitchen", "charlotteslivelykitchen.com", ["British", "Baking"]),
    ("Apply to Face Blog", "applytofaceblog.com", ["British", "Baking"]),
    ("The Petite Cook", "thepetitecook.com", ["Italian", "British"]),
    ("Inside the Rustic Kitchen", "insidetherustickitchen.com", ["Italian", "European"]),
    ("Marcellina in Cucina", "marcellinaincucina.com", ["Italian", "Baking"]),
    ("Italian Recipe Book", "italianrecipebook.com", ["Italian", "Traditional"]),
    ("The Greek Foodie", "thegreekfoodie.com", ["Greek", "Mediterranean"]),
    ("My Greek Dish", "mygreekdish.com", ["Greek", "Mediterranean"]),
    ("Real Greek Recipes", "realgreekrecipes.com", ["Greek", "Mediterranean"]),
    ("Spanish Sabores", "spanishsabores.com", ["Spanish", "European"]),
    ("Spain on a Fork", "spainonafork.com", ["Spanish", "Mediterranean"]),
    ("The Mediterranean Fork", "themediterraneanfork.com", ["Mediterranean", "European"]),
    ("Polonist", "polonist.com", ["Polish", "European"]),
    ("Where Is My Spoon", "whereismyspoon.co", ["German", "European"]),
    ("My German Recipes", "mygerman.recipes", ["German", "European"]),
    ("The Spruce Eats", "thespruceeats.com", ["Global", "Everyday"]),
    ("RecipeTin Japan", "japan.recipetineats.com", ["Japanese", "Asian"]),
    ("Marion's Kitchen", "marionskitchen.com", ["Asian", "Australian"]),
    ("Wandercooks", "wandercooks.com", ["Global", "Australian"]),
    ("Sugar Salt Magic", "sugarsaltmagic.com", ["Australian", "Baking"]),
    ("Sprinkles and Sprouts", "sprinklesandsprouts.com", ["Australian", "Everyday"]),
    ("It's Not Complicated Recipes", "itsnotcomplicatedrecipes.com", ["Australian", "Everyday"]),
    ("Sweet Caramel Sunday", "sweetcaramelsunday.com", ["Australian", "Everyday"]),
    ("The Kiwi Country Girl", "thekiwicountrygirl.com", ["New Zealand", "Baking"]),
    ("Chelsea Winter", "chelseawinter.co.nz", ["New Zealand", "Everyday"]),
    ("VJ Cooks", "vjcooks.com", ["New Zealand", "Family"]),
    ("Nora Cooks", "noracooks.com", ["Vegan", "Plant-based"]),
    ("Rainbow Plant Life", "rainbowplantlife.com", ["Vegan", "Plant-based"]),
    ("The First Mess", "thefirstmess.com", ["Vegan", "Plant-based"]),
    ("It Doesn't Taste Like Chicken", "itdoesnttastelikechicken.com", ["Vegan", "Plant-based"]),
    ("Lazy Cat Kitchen", "lazycatkitchen.com", ["Vegan", "Plant-based"]),
    ("The Conscious Plant Kitchen", "theconsciousplantkitchen.com", ["Vegan", "Low-carb"]),
    ("Rainbow Nourishments", "rainbownourishments.com", ["Vegan", "Baking"]),
    ("Addicted to Dates", "addictedtodates.com", ["Vegan", "Baking"]),
    ("Beaming Baker", "beamingbaker.com", ["Vegan", "Gluten-free"]),
    ("The Bojon Gourmet", "bojongourmet.com", ["Gluten-free", "Baking"]),
    ("Gluten Free on a Shoestring", "glutenfreeonashoestring.com", ["Gluten-free", "Baking"]),
    ("The Loopy Whisk", "theloopywhisk.com", ["Gluten-free", "Baking"]),
    ("Mama Knows Gluten Free", "mamaknowsglutenfree.com", ["Gluten-free", "Family"]),
    ("Texanerin Baking", "texanerin.com", ["Baking", "Gluten-free"]),
    ("Sally's Baking Addiction", "sallysbakingaddiction.com", ["Baking", "Desserts"]),
    ("Preppy Kitchen", "preppykitchen.com", ["Baking", "Desserts"]),
    ("Cloudy Kitchen", "cloudykitchen.com", ["Baking", "Desserts"]),
    ("Butternut Bakery", "butternutbakeryblog.com", ["Baking", "Desserts"]),
    ("Handle the Heat", "handletheheat.com", ["Baking", "Desserts"]),
    ("The Pancake Princess", "thepancakeprincess.com", ["Baking", "Desserts"]),
]

SSL = ssl.create_default_context()
HEADERS = {"User-Agent": "StockedMacSourceAudit/1.0 (+https://sowensstudios.com)"}


def fetch(url: str, limit: int = 131072) -> tuple[int, str, str]:
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=12, context=SSL) as response:
            return response.status, response.geturl(), response.read(limit).decode("utf-8", "ignore")
    except (urllib.error.URLError, TimeoutError, socket.timeout, ValueError):
        return 0, url, ""


def slug(domain: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", domain.lower()).strip("-")


def audit(name: str, domain: str, tags: list[str]) -> dict | None:
    base = f"https://{domain}"
    status, final_url, html = fetch(base)
    if status < 200 or status >= 400:
        status, final_url, html = fetch(f"https://www.{domain}")
    if status < 200 or status >= 400:
        print(f"skip unreachable: {domain}", file=sys.stderr)
        return None
    language = re.search(r"<html[^>]+lang=[\"']([^\"']+)", html, re.I)
    if language and not language.group(1).lower().startswith("en"):
        print(f"skip non-English markup ({language.group(1)}): {domain}", file=sys.stderr)
        return None
    root = final_url.rstrip("/")
    sitemap_candidates = [root + "/sitemap.xml", root + "/sitemap_index.xml", root + "/wp-sitemap.xml"]
    working_sitemaps = []
    for sitemap in sitemap_candidates:
        sitemap_status, sitemap_final, body = fetch(sitemap, 32768)
        if 200 <= sitemap_status < 400 and ("<urlset" in body or "<sitemapindex" in body):
            working_sitemaps.append(sitemap_final)
            break
    if not working_sitemaps:
        print(f"skip no sitemap: {domain}", file=sys.stderr)
        return None
    return {
        "id": slug(domain), "name": name, "domains": sorted({domain, urllib.parse.urlparse(root).hostname or domain}),
        "baseURL": root, "enabled": True, "discoveryEnabled": True,
        "discoveryMode": "sitemapOnly", "parserMode": "nativeFirst",
        "minimumDelaySeconds": 3, "maximumConcurrency": 1, "dailyRequestLimit": 100,
        "robotsRequired": True, "imageDownloadEnabled": True, "sitemapURLs": working_sitemaps,
        "recipeURLPatterns": [], "excludedURLPatterns": ["/author/", "/page/", "/shop/", "/video/"],
        "tags": ["English"] + tags + ["Structured Data"],
        "notes": "English-language global recipe publisher; HTTPS homepage and XML sitemap verified by the Stocked source audit.",
        "health": "unknown",
    }


def main() -> int:
    catalog = json.loads(JSON_PATH.read_text())
    existing = {domain.removeprefix("www.").lower() for row in catalog for domain in row["domains"]}
    installed = [row for row in catalog if "English" in row.get("tags", [])]
    needed = max(0, 100 - len(installed))
    additions = []
    if needed:
        pending = [candidate for candidate in CANDIDATES if candidate[1].removeprefix("www.").lower() not in existing]
        # Different domains can be checked independently; each individual source remains
        # strictly serial and bounded to avoid hammering any publisher.
        with ThreadPoolExecutor(max_workers=12) as pool:
            audited = list(pool.map(lambda candidate: audit(*candidate), pending))
        additions = [record for record in audited if record is not None][:needed]
        if len(additions) != needed:
            print(f"audit yielded {len(additions)} of {needed} required sources; refusing partial catalog update", file=sys.stderr)
            return 1
    updated = catalog + additions
    encoded = json.dumps(updated, ensure_ascii=False, separators=(",", ":"))
    JSON_PATH.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n")

    swift = SWIFT_PATH.read_text()
    replaced, count = re.subn(
        r'(static let embeddedJSON = #"""\n).*?(\n"""#)',
        lambda match: match.group(1) + encoded + match.group(2),
        swift,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError("could not locate embedded source catalog")
    SWIFT_PATH.write_text(replaced)
    print(f"added {len(additions)} sources; catalog now has {len(updated)}")
    for row in additions:
        print(f"{row['name']}\t{row['baseURL']}\t{row['sitemapURLs'][0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
