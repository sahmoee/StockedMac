#!/usr/bin/env node

// Keeps the editable, bundled, and compiled fallback source catalogs identical.
// Run from anywhere: node scripts/update-source-catalog.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const bundledPath = path.join(root, "StockedMac", "default-sources.json");
const rootPath = path.join(root, "default-sources.json");
const swiftPath = path.join(root, "StockedMac", "Harvest", "DefaultSourceCatalog.swift");

const candidates = [
  ["acouplecooks", "A Couple Cooks", "https://www.acouplecooks.com"],
  ["acozykitchen", "A Cozy Kitchen", "https://www.acozykitchen.com"],
  ["addapinch", "Add a Pinch", "https://addapinch.com"],
  ["africanbites", "Immaculate Bites", "https://www.africanbites.com"],
  ["alexandracooks", "Alexandra's Kitchen", "https://alexandracooks.com"],
  ["anitalianinmykitchen", "An Italian in My Kitchen", "https://anitalianinmykitchen.com"],
  ["barefeetinthekitchen", "Barefeet in the Kitchen", "https://barefeetinthekitchen.com"],
  ["bakerbynature", "Baker by Nature", "https://bakerbynature.com"],
  ["bakingmischief", "Baking Mischief", "https://bakingmischief.com"],
  ["bellyfull", "Belly Full", "https://bellyfull.net"],
  ["biggerbolderbaking", "Bigger Bolder Baking", "https://www.biggerbolderbaking.com"],
  ["bowlofdelicious", "Bowl of Delicious", "https://www.bowlofdelicious.com"],
  ["carlsbadcravings", "Carlsbad Cravings", "https://carlsbadcravings.com"],
  ["chewoutloud", "Chew Out Loud", "https://www.chewoutloud.com"],
  ["closetcooking", "Closet Cooking", "https://www.closetcooking.com"],
  ["cookiesandcups", "Cookies and Cups", "https://cookiesandcups.com"],
  ["copykat", "CopyKat Recipes", "https://copykat.com"],
  ["culinaryhill", "Culinary Hill", "https://www.culinaryhill.com"],
  ["daringgourmet", "The Daring Gourmet", "https://www.daringgourmet.com"],
  ["dinneratthezoo", "Dinner at the Zoo", "https://www.dinneratthezoo.com"],
  ["eatingbirdfood", "Eating Bird Food", "https://www.eatingbirdfood.com"],
  ["feastingathome", "Feasting at Home", "https://www.feastingathome.com"],
  ["feelgoodfoodie", "Feel Good Foodie", "https://feelgoodfoodie.net"],
  ["fifteenspatulas", "Fifteen Spatulas", "https://www.fifteenspatulas.com"],
  ["forksoverknives", "Forks Over Knives", "https://www.forksoverknives.com"],
  ["grandbabycakes", "Grandbaby Cakes", "https://grandbaby-cakes.com"],
  ["houseofnasheats", "House of Nash Eats", "https://houseofnasheats.com"],
  ["inspiredtaste", "Inspired Taste", "https://www.inspiredtaste.net"],
  ["iowagirleats", "Iowa Girl Eats", "https://iowagirleats.com"],
  ["jocooks", "Jo Cooks", "https://www.jocooks.com"],
  ["joyfoodsunshine", "JoyFoodSunshine", "https://joyfoodsunshine.com"],
  ["natashaskitchen", "Natasha's Kitchen", "https://natashaskitchen.com"],
  ["noracooks", "Nora Cooks", "https://www.noracooks.com"],
  ["preppykitchen", "Preppy Kitchen", "https://preppykitchen.com"],
  ["alisoneroman", "Alison Roman", "https://www.alisoneroman.com"],
  ["bettycrocker", "Betty Crocker", "https://www.bettycrocker.com"],
  ["eatingwell", "EatingWell", "https://www.eatingwell.com"],
  ["pickuplimes", "Pick Up Limes", "https://www.pickuplimes.com"],
  ["sipandfeast", "Sip and Feast", "https://sipandfeast.com"],
  ["dinnerthendessert", "Dinner, then Dessert", "https://dinnerthendessert.com"],
];

const empiricalPriority = ["gimmesomeoven", "thekitchn", "therecipecritic", "delish", "tasty"];
const current = JSON.parse(fs.readFileSync(bundledPath, "utf8"));
const candidateIDs = new Set(candidates.map(([id]) => id));
const base = current.filter(source => !candidateIDs.has(source.id));
const byID = new Map(base.map(source => [source.id, source]));
const proven = empiricalPriority.map(id => byID.get(id)).filter(Boolean);
const provenIDs = new Set(proven.map(source => source.id));
const feeds = base.filter(source => source.discoveryMode === "feedOnly" && !provenIDs.has(source.id));
const remaining = base.filter(source => !provenIDs.has(source.id) && source.discoveryMode !== "feedOnly");

const additions = candidates.map(([id, name, baseURL], index) => {
  const host = new URL(baseURL).hostname.replace(/^www\./, "");
  const limited = id === "dinnerthendessert";
  const wpOnly = id === "sipandfeast";
  return {
    id, name, domains: [host], baseURL,
    enabled: true,
    discoveryEnabled: !limited,
    discoveryMode: limited ? "directOnly" : "sitemapOnly",
    parserMode: "nativeFirst",
    minimumDelaySeconds: 3,
    maximumConcurrency: 1,
    dailyRequestLimit: 100,
    robotsRequired: true,
    imageDownloadEnabled: true,
    sitemapURLs: [wpOnly ? `${baseURL}/wp-sitemap.xml` : `${baseURL}/sitemap.xml`],
    recipeURLPatterns: [],
    excludedURLPatterns: ["/category/", "/tag/", "/author/", "/page/", "/shop/", "/video/"],
    tags: ["Recipe Site", "Structured Data", index < 34 ? "Discovery Friendly" : "Supported Parser"],
    notes: limited
      ? "Supported structured-recipe parser, but the August 2026 sitemap audit returned 403; direct import remains available and robots policy is always enforced."
      : "Supported structured-recipe parser; robots and sitemap endpoints were reachable in the August 2026 source audit.",
    health: limited ? "limited" : "unknown",
  };
});

const catalog = [...proven, ...additions, ...remaining, ...feeds];
if (catalog.length !== 150 || new Set(catalog.map(source => source.id)).size !== 150) {
  throw new Error(`Expected 150 unique sources, got ${catalog.length}`);
}

const pretty = JSON.stringify(catalog, null, 2) + "\n";
fs.writeFileSync(bundledPath, pretty);
fs.writeFileSync(rootPath, pretty);

let swift = fs.readFileSync(swiftPath, "utf8");
swift = swift.replace(/the same 100 sources now/, "the complete source catalog now");
swift = swift.replace(/The catalog is the top 50 American[\s\S]*?\(reddit and friends, discoveryMode "feedOnly"\)\./,
  "The catalog is priority ordered from proven imports through audited structured-recipe sites, then community feeds (discoveryMode \"feedOnly\").");
swift = swift.replace(/(#\"\"\"\n)[\s\S]*?(\n\"\"\"#)/, `$1${JSON.stringify(catalog)}$2`);
fs.writeFileSync(swiftPath, swift);

console.log(`Wrote ${catalog.length} priority-ordered sources (added ${additions.length}).`);
