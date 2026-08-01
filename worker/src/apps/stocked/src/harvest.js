// harvest.js — the Mac Harvester's cloud cache (Build 91 of Stocked for Mac).
//
// The Mac app browses recipe sites, verifies and approves recipes, and pushes the
// results here so they survive that one Mac and become readable by every device on the
// key. cPanel is retired as a store (see content.js); this cache lives in KV (recipes,
// and images when R2 is not bound) or R2 (images, preferred via env.MEDIA).
//
//   POST /harvest/cache        { schemaVersion, recipes: [...] }   ≤ 50 per call
//   POST /harvest/image        { id, imageBase64, mediaType }      ≤ 1 MB decoded
//   GET  /harvest/recipes      → { version, count, recipes: [...] }  (edge-cached 10 min)
//   GET  /harvest/img/<id>.jpg → image bytes, 30-day edge cache
//
// All four sit behind the same X-Stocked-Key gate as every other route. Recipes are
// stored one KV key per recipe (harvest:recipe:<id>) plus an id index (harvest:index),
// so re-pushing the same recipe overwrites in place and never duplicates.

import { json, errJson, withCors, background, logEvent } from "./util.js";

const INDEX_KEY = "harvest:index";
const recipeKey = (id) => `harvest:recipe:${id}`;
const imageKVKey = (id) => `harvest:img:${id}`;
const imageR2Key = (id) => `harvest/img/${id}`;

const MAX_RECIPES_PER_CALL = 50;
const MAX_INDEX = 5000;                    // keep the newest N ids
const MAX_IMAGE_BYTES = 1024 * 1024;       // decoded
const LIST_TTL_S = 600;                    // /harvest/recipes edge cache
const IMG_TTL_S = 30 * 24 * 3600;

const LIST_CACHE_URL = "https://harvest.internal/recipes";

const cleanId = (raw) =>
  String(raw || "").replace(/[^A-Za-z0-9-]/g, "").slice(0, 64);

async function readIndex(env) {
  try { return (await env.CROWD.get(INDEX_KEY, { type: "json" })) || []; }
  catch { return []; }
}

/** POST /harvest/cache — upsert a batch of recipes. */
export async function handleHarvestCache(request, env, ctx, requestId) {
  if (!env.CROWD) return errJson(503, "Harvest KV not bound", { code: "unavailable", requestId });

  let body;
  try { body = await request.json(); } catch {
    return errJson(400, "Invalid JSON body", { code: "invalidInput", requestId });
  }
  const recipes = Array.isArray(body && body.recipes) ? body.recipes : null;
  if (!recipes || !recipes.length) {
    return errJson(400, "Required: recipes (non-empty array)", { code: "invalidInput", requestId });
  }
  if (recipes.length > MAX_RECIPES_PER_CALL) {
    return errJson(400, `At most ${MAX_RECIPES_PER_CALL} recipes per call`, { code: "invalidInput", requestId });
  }

  const index = await readIndex(env);
  const known = new Set(index);
  let stored = 0;

  for (const recipe of recipes) {
    const id = cleanId(recipe && recipe.id);
    if (!id || typeof recipe.title !== "string" || !recipe.title.trim()) continue;
    if (!Array.isArray(recipe.ingredients) || !Array.isArray(recipe.instructions)) continue;
    try {
      await env.CROWD.put(recipeKey(id), JSON.stringify({ ...recipe, id, updatedAt: new Date().toISOString() }));
      if (!known.has(id)) { known.add(id); index.push(id); }
      stored++;
    } catch (e) {
      logEvent({ requestId, event: "harvestKVWriteError", error: String((e && e.message) || e) });
      return errJson(500, "KV write failed", { code: "internalError", requestId });
    }
  }

  const trimmed = index.slice(-MAX_INDEX);
  try { await env.CROWD.put(INDEX_KEY, JSON.stringify(trimmed)); } catch {}

  // The list changed; drop the edge copy so readers see the update within a request.
  background(ctx, caches.default.delete(LIST_CACHE_URL).catch(() => {}));

  return json({ ok: true, stored, total: trimmed.length });
}

/** POST /harvest/image — store one recipe image (R2 when bound, else KV base64). */
export async function handleHarvestImage(request, env, ctx, requestId) {
  let body;
  try { body = await request.json(); } catch {
    return errJson(400, "Invalid JSON body", { code: "invalidInput", requestId });
  }
  const id = cleanId(body && body.id);
  const b64 = body && body.imageBase64;
  if (!id || typeof b64 !== "string" || !b64) {
    return errJson(400, "Required: id, imageBase64", { code: "invalidInput", requestId });
  }

  let bytes;
  try {
    const bin = atob(b64);
    if (bin.length > MAX_IMAGE_BYTES) {
      return errJson(413, "Image too large (1 MB max)", { code: "payloadTooLarge", requestId });
    }
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    return errJson(400, "imageBase64 is not valid base64", { code: "invalidInput", requestId });
  }

  const mediaType = typeof body.mediaType === "string" && body.mediaType.startsWith("image/")
    ? body.mediaType : "image/jpeg";

  try {
    if (env.MEDIA) {
      await env.MEDIA.put(imageR2Key(id), bytes, { httpMetadata: { contentType: mediaType } });
    } else if (env.CROWD) {
      await env.CROWD.put(imageKVKey(id), JSON.stringify({ mediaType, data: b64 }));
    } else {
      return errJson(503, "No image store bound", { code: "unavailable", requestId });
    }
  } catch (e) {
    logEvent({ requestId, event: "harvestImageWriteError", error: String((e && e.message) || e) });
    return errJson(500, "Image write failed", { code: "internalError", requestId });
  }

  return json({ ok: true, id, bytes: bytes.length, store: env.MEDIA ? "r2" : "kv" });
}

/** GET /harvest/recipes — the whole cache, newest last, edge-cached briefly. */
export async function handleHarvestRecipes(request, env, ctx, requestId) {
  if (!env.CROWD) return errJson(503, "Harvest KV not bound", { code: "unavailable", requestId });

  try {
    const hit = await caches.default.match(LIST_CACHE_URL);
    if (hit) return withCors(hit);
  } catch {}

  const index = await readIndex(env);
  const recipes = [];
  // KV reads are fast but sequential awaits add up; batch them.
  const BATCH = 20;
  for (let i = 0; i < index.length; i += BATCH) {
    const chunk = index.slice(i, i + BATCH);
    const values = await Promise.all(chunk.map((id) => env.CROWD.get(recipeKey(id), { type: "json" }).catch(() => null)));
    for (const value of values) if (value) recipes.push(value);
  }

  const payload = JSON.stringify({ version: 1, count: recipes.length, recipes });
  const headers = { "Content-Type": "application/json", "Cache-Control": `max-age=${LIST_TTL_S}` };
  const response = new Response(payload, { status: 200, headers });
  background(ctx, caches.default.put(LIST_CACHE_URL, new Response(payload, { status: 200, headers })).catch(() => {}));
  return withCors(response);
}

/** GET /harvest/img/<id>[.jpg] — one cached image, long edge cache. */
export async function handleHarvestImageGet(request, env, ctx, requestId, pathname) {
  const raw = pathname.slice("/harvest/img/".length).replace(/\.(jpe?g|png|webp)$/i, "");
  const id = cleanId(raw);
  if (!id) return errJson(404, "Not found", { code: "notFound", requestId });

  const cacheKey = "https://harvest.internal/img/" + id;
  try {
    const hit = await caches.default.match(cacheKey);
    if (hit) return withCors(hit);
  } catch {}

  let bodyBytes = null;
  let mediaType = "image/jpeg";

  if (env.MEDIA) {
    try {
      const object = await env.MEDIA.get(imageR2Key(id));
      if (object) {
        bodyBytes = await object.arrayBuffer();
        mediaType = (object.httpMetadata && object.httpMetadata.contentType) || mediaType;
      }
    } catch {}
  }
  if (!bodyBytes && env.CROWD) {
    try {
      const stored = await env.CROWD.get(imageKVKey(id), { type: "json" });
      if (stored && stored.data) {
        const bin = atob(stored.data);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        bodyBytes = bytes.buffer;
        mediaType = stored.mediaType || mediaType;
      }
    } catch {}
  }
  if (!bodyBytes) return errJson(404, "Image not found", { code: "notFound", requestId });

  const headers = { "Content-Type": mediaType, "Cache-Control": `max-age=${IMG_TTL_S}` };
  const out = new Response(bodyBytes, { status: 200, headers });
  const copy = new Response(bodyBytes.slice(0), { status: 200, headers });
  background(ctx, caches.default.put(cacheKey, copy).catch(() => {}));
  return withCors(out);
}
