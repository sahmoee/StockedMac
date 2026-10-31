#!/usr/bin/env node

// Keeps the editable, bundled, and compiled fallback source catalogs identical.
// The bundled JSON is canonical; this script never reconstructs or truncates it.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const bundledPath = path.join(root, "StockedMac", "default-sources.json");
const rootPath = path.join(root, "default-sources.json");
const swiftPath = path.join(root, "StockedMac", "Harvest", "DefaultSourceCatalog.swift");

const catalog = JSON.parse(fs.readFileSync(bundledPath, "utf8"));
if (!Array.isArray(catalog) || catalog.length === 0) throw new Error("Bundled source catalog must be a non-empty array");
const ids = catalog.map(source => source.id);
if (ids.some(id => typeof id !== "string" || id.length === 0)) throw new Error("Every source must have a non-empty string ID");
if (new Set(ids).size !== ids.length) throw new Error("Bundled source catalog contains duplicate IDs");
for (const source of catalog) {
  if (!Array.isArray(source.domains) || source.domains.length === 0) throw new Error(`Source ${source.id} has no domains`);
  if (!Array.isArray(source.sitemapURLs)) throw new Error(`Source ${source.id} has no sitemap URL array`);
}

const pretty = JSON.stringify(catalog, null, 2) + "\n";
fs.writeFileSync(bundledPath, pretty);
fs.writeFileSync(rootPath, pretty);

const swift = fs.readFileSync(swiftPath, "utf8");
const embeddedPattern = /(#"""\n)[\s\S]*?(\n"""#)/;
if (!embeddedPattern.test(swift)) throw new Error("Could not locate the embedded Swift source catalog");
const updated = swift.replace(embeddedPattern, `$1${JSON.stringify(catalog)}$2`);
fs.writeFileSync(swiftPath, updated);
console.log(`Synchronized ${catalog.length} source profiles.`);
