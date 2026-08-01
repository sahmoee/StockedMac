# CROSS-PROJECT-SYNC — this folder is the **Unified Worker** (`Documents/worker`)

> Identification for any chat: this is the Cloudflare Worker monorepo
> (`wrangler.toml`, `src/apps/{stocked,astra,atlas,sesh}`) serving
> `api.sowensstudios.com`. The Mac app lives in `Documents/Stocked Mac`; the iOS app
> in `Documents/Stocked 2`. Every update applied to one project must be recorded in
> the other folders' copies of this file.

## Applied updates

### 2026-08-01 — harvest cache (for Stocked Mac Build 91)
- New `src/apps/stocked/src/harvest.js`; `index.js` wires 4 routes and bumps
  `WORKER_VERSION` to `2026-08-01.1`, capability `harvest-cache`:
  - `POST /harvest/cache` — upsert ≤ 50 recipes → KV `harvest:recipe:<id>` + `harvest:index`
  - `POST /harvest/image` — one image ≤ 1 MB → R2 `env.MEDIA` if bound, else KV base64
  - `GET /harvest/recipes` — full cache, 10-min edge cache
  - `GET /harvest/img/<id>.jpg` — 30-day edge cache
- No new bindings needed (`CROWD` KV reused). Shared-key gated like everything else.
- Caller: Mac app Build 91 Browse section (`HarvestCloudSync.swift`). Recipes are
  guaranteed to carry an image. cPanel remains retired; this cache is its successor.
- iOS impact: none required; the two GET routes are available for the app to adopt.
