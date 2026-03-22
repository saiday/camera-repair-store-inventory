# Cloudflare Pages Hosting — Design Spec

## Overview

Migrate the camera repair inventory system from a local Python HTTP server to Cloudflare Pages with Workers. The system remains file-based and git-based — Markdown files in the repository are the source of truth. Mutations (create/edit items) commit via the GitHub API and trigger a Cloudflare Pages rebuild. Customer-facing item pages allow the shop to share repair status with customers behind per-item password protection.

## Architecture Summary

- **Static hosting:** Cloudflare Pages serves pre-generated HTML, CSS, JS, and JSON
- **Workers (Pages Functions):** handle password gating and GitHub API commits
- **Build step:** bash scripts generate all static output from `data/repairs/` Markdown files
- **Mutations:** entry form → Worker → GitHub API commit → push triggers rebuild
- **Local dev:** existing `server.sh` / `server.py` workflow remains fully functional

## Directory Structure Changes

### Data directory restructure

`data/repairs/` gains year/month nesting based on `received_date`:

```
data/repairs/
  2026/
    03/
      CAM-20260322-EOS-R5-001/
        item.md
        logs/
      LENS-20260315-SEL-24-70-GM-001/
        item.md
        logs/
    04/
      ...
```

Sequence number lookups (`NNN`) scan only the relevant `YYYY/MM/` directory via GitHub API, matching the existing per-type+date+model scoping.

### Generated data directory

`web/_data/` contains all build-generated files. It lives inside the Pages output directory (`web/`) so that Cloudflare Workers can read it via `env.ASSETS.fetch()`. Nothing in `web/_data/` is source-controlled — it is produced by `build.sh` at build time.

The middleware blocks direct browser access to `web/_data/` paths (requires shop password). Workers read these files internally via the ASSETS binding, bypassing the middleware.

```
web/_data/
  published.json                    # item ID → salted password hash (Worker-only)
  items.json                        # all items frontmatter (lightweight listing)
  owners.json                       # owner registry (generated from all items)
  items/
    CAM-20260322-EOS-R5-001.json    # full item content (fetched on demand for editing)
    LENS-20260315-SEL-24-70-GM-001.json
    ...
```

- `items.json` — frontmatter only, used for search/listing on the entry page (replaces `GET /api/items`)
- `owners.json` — generated at build time from all items' owner fields, deduplicated. For local dev, `update-owners.sh` writes to `data/owners.json` as before; the build script generates `web/_data/owners.json` separately
- `items/{id}.json` — full item content including body sections, fetched on demand when editing (replaces `GET /api/item/<id>/raw`)
- `published.json` — maps published item IDs to salted password hashes, consumed only by the Worker via `env.ASSETS.fetch()`. Although technically inside `web/`, the middleware requires shop authentication for `/_data/*` paths, so it is not publicly accessible

### Cloudflare Pages Functions

```
functions/
  _middleware.js            # shop password gate for admin routes
  api/
    create.js               # POST: create item via GitHub API commit
    update.js               # POST: update item via GitHub API commit
  item/
    [id].js                 # customer page password gate
```

### Full project structure

```
camera-repair-store-inventory/
├── data/
│   └── repairs/
│       └── YYYY/
│           └── MM/
│               └── {ITEM_ID}/
│                   ├── item.md
│                   └── logs/
├── scripts/
│   ├── build.sh                   # main build entry point for Cloudflare Pages
│   ├── migrate-directory.sh       # one-time migration: flat → YYYY/MM/ nesting
│   ├── generate-dashboard.sh      # existing, extended
│   ├── generate-customer-pages.sh # new: builds published item pages
│   ├── generate-manifest.sh       # new: builds web/_data/published.json
│   ├── parse-item.sh              # existing
│   ├── create-item.sh             # existing (updated for new dir structure)
│   ├── update-item.sh             # existing (updated for new dir structure)
│   ├── update-owners.sh           # existing (local dev: data/owners.json, build: web/_data/)
│   ├── server.sh                  # kept for local dev
│   └── server.py                  # kept for local dev (updated for nested dirs)
├── web/
│   ├── entry.html
│   ├── dashboard.html             # generated at build time
│   ├── customer/                  # generated: one HTML per published item
│   │   └── {ITEM_ID}.html
│   ├── _data/                     # build-generated, not source-controlled
│   │   ├── published.json
│   │   ├── items.json
│   │   ├── owners.json
│   │   └── items/
│   └── static/
│       ├── style.css
│       ├── entry.js
│       └── dashboard.js
├── functions/                     # Cloudflare Pages Functions (JS)
│   ├── _middleware.js
│   ├── api/
│   │   ├── create.js
│   │   └── update.js
│   └── item/
│       └── [id].js
├── docs/
│   ├── format.md
│   ├── cloud-architecture.md      # reusable architecture reference
│   └── cloudflare-setup.md        # non-tech setup guide
├── wrangler.toml
├── CLAUDE.md
└── README.md
```

## Frontmatter Changes

One new field added to `item.md`:

```yaml
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345678"
status: in_progress
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
page_password:
---
```

### `page_password`

- **Empty** — item is not published, no customer page generated
- **Has a value** — item is published, that value is the customer page password
- When status becomes `delivered`, `page_password` is cleared (customer page taken down)
- The entry form UI pre-fills this field with `owner_contact` when the shop owner initiates publishing, but the shop owner can change it
- Default for new items: empty (not published)

The file is the source of truth — if someone manually sets `page_password` in the frontmatter, the item is published. No separate `published` flag needed.

## Password Protection

### Shop owner (entry + dashboard)

1. Owner visits any admin route (`/`, `/entry`, `/dashboard`, etc.)
2. `_middleware.js` checks for a `shop_session` cookie
3. **No cookie / expired →** Worker serves a password prompt page
4. Owner submits password → Worker compares against `SHOP_PASSWORD` env var
5. **Match →** Worker sets `shop_session` cookie (HttpOnly, Secure, SameSite=Strict, 24h expiry) and serves the requested page
6. **Mismatch →** re-prompt with error message
7. Subsequent requests within the session → cookie is valid, Worker passes through

### Customer (item page)

1. Customer visits `/item/{ITEM_ID}`
2. `[id].js` reads `web/_data/published.json` via `env.ASSETS.fetch()` to look up the item
3. **Not found (unpublished or delivered) →** 404
4. **Found →** Worker checks for a `customer_session_{item_id}` cookie
5. **No cookie / expired →** Worker serves a password prompt page
6. Customer submits password → Worker hashes it and compares against the manifest
7. **Match →** Worker sets a per-item cookie (HttpOnly, Secure, SameSite=Strict, 7-day expiry) and serves `web/customer/{ITEM_ID}.html`
8. **Mismatch →** re-prompt with error message
9. Subsequent visits within the session → cookie valid, page served directly

### Password sources

- **Shop password:** `SHOP_PASSWORD` environment variable (set via `wrangler secret put`)
- **Customer passwords:** at build time, `generate-manifest.sh` reads each item's `page_password`, generates a random salt, hashes with SHA-256 (using `shasum -a 256` for macOS compatibility), and writes to `web/_data/published.json`:
  ```json
  {
    "CAM-20260322-EOS-R5-001": { "salt": "random-hex-string", "hash": "sha256:abc..." },
    "LENS-20260315-SEL-24-70-GM-001": { "salt": "random-hex-string", "hash": "sha256:def..." }
  }
  ```
  Salted hashes are required because passwords often default to phone numbers, which have a small keyspace vulnerable to brute-force against plain SHA-256.

## Build Pipeline

Cloudflare Pages build command: `./scripts/build.sh`

`build.sh` orchestrates in order:

1. **Parse all items** — walk `data/repairs/YYYY/MM/*/item.md`, run `parse-item.sh` on each, collect frontmatter JSON into `web/_data/items.json`, write full item JSON to `web/_data/items/{id}.json`
2. **Generate owners** — scan all items, deduplicate `{name, contact}` pairs, write to `web/_data/owners.json`
3. **Generate dashboard** — run `generate-dashboard.sh` (outputs `web/dashboard.html`)
4. **Generate customer pages** — for each item where `page_password` is non-empty AND status is not `delivered`, generate `web/customer/{ITEM_ID}.html` with item details (strips owner_name and owner_contact)
5. **Generate manifest** — for each published item, generate a random salt, hash `salt + page_password` with SHA-256 (via `shasum -a 256` on macOS or `sha256sum` on Linux), write to `web/_data/published.json`

**Output directory** (Cloudflare Pages serves): `web/`

## Worker Flows (Pages Functions)

### `functions/_middleware.js` — shop admin gate

- Applies to all routes except `/item/*`
- On POST to the password form endpoint: validates submitted password against `SHOP_PASSWORD` env var, sets cookie or re-prompts (handles its own auth POST before the cookie check)
- On all other requests: checks `shop_session` cookie → valid? pass through : show password prompt
- This means `/_data/*` paths (items.json, owners.json, etc.) require shop authentication — they contain owner data and are not publicly accessible
- Sets HttpOnly, Secure, SameSite=Strict cookie, 24h expiry

### `functions/item/[id].js` — customer page gate

- Reads `web/_data/published.json` via `env.ASSETS.fetch()` (bypasses middleware)
- Not found → 404
- Checks `customer_session_{id}` cookie → valid? serve `web/customer/{id}.html` : show password prompt
- Validates password: hashes submitted password with the item's stored salt, compares against stored hash
- Sets per-item cookie, 7-day expiry

### `functions/api/create.js` — create item

- Receives form data from entry page
- Generates item ID:
  - Determines `YYYY/MM/` path from `received_date`
  - Lists `data/repairs/YYYY/MM/` via GitHub API to find existing IDs with same type+date+model prefix
  - Increments to next sequence number
- Builds `item.md` content (frontmatter + body)
- Commits new file to repo via GitHub API (using `GITHUB_TOKEN` env var)
- **Race condition handling:** uses GitHub API's "create file" endpoint which fails if the path already exists. On conflict error (HTTP 409 or 422), retries with the next sequence number (max 3 retries)
- Returns new item ID to client
- Push triggers Cloudflare Pages rebuild

### `functions/api/update.js` — update item

- Receives form data + item ID
- Reads current `item.md` via GitHub API (includes file SHA)
- Applies changes (field updates, cost append, status change)
- If status → `delivered`, clears `page_password`
- Commits updated file to repo via GitHub API (provides SHA for conditional update — fails if file was modified concurrently)
- The existing `POST /api/deliver` endpoint is consolidated here — delivering is an update with `status: delivered`
- Returns success, rebuild triggered

## Shop UI Changes

### Entry page

- **New `page_password` field** — text input with a publish action that auto-fills `owner_contact`. The shop owner can modify the password before saving.
- **Copyable message block** — visible when `page_password` is set:
  ```
  你的維修單：{URL}，請使用 {Password} 作為密碼進行查看
  ```
  With a copy button for easy sharing with customers.
- **Data fetching** — switches from API calls to static JSON fetches (`/_data/items.json`, `/_data/items/{id}.json`, `/_data/owners.json`)
- **Form submit** — POSTs to `/api/create` or `/api/update` (Worker endpoints) instead of the Python server

### Dashboard

- No major changes — still pre-generated at build time
- Card links to entry page for editing remain the same

### Customer page (new)

- Generated at build time, one HTML per published item
- Shows: category, brand, model, serial number, status, received/delivered date, repair description, cost log
- Strips: owner_name, owner_contact
- Styled consistently with existing pages (uses `style.css`)
- Read-only, no edit capability

## Local Dev vs Production

### Production (Cloudflare Pages)

- Build: `./scripts/build.sh` generates `web/_data/`, `web/customer/`, `web/dashboard.html`
- Serve: Cloudflare Pages serves `web/` as static, Functions handle auth + API
- Mutations: Worker commits via GitHub API → push → rebuild

### Local dev (updated for new directory structure)

- `./scripts/server.sh` starts Python server on port 8787
- `create-item.sh` / `update-item.sh` work directly (with hooks, or REPL mode)
- No Workers, no GitHub API — direct file operations
- Run `./scripts/build.sh` locally to preview the static output
- `server.py` updated to scan nested `data/repairs/YYYY/MM/*/` directories
- `update-owners.sh` writes to `data/owners.json` for local dev (build script writes to `web/_data/owners.json`)

The bash scripts and local server remain fully functional. Cloudflare is an additional deployment target, not a replacement for the local workflow.

### Migration

`scripts/migrate-directory.sh` — one-time script to restructure existing flat `data/repairs/{ITEM_ID}/` into `data/repairs/YYYY/MM/{ITEM_ID}/` based on each item's `received_date` frontmatter field. Run once before switching to the new structure.

## Environment Variables

Set via Cloudflare dashboard or `wrangler secret put`:

| Variable | Purpose |
|----------|---------|
| `SHOP_PASSWORD` | Admin password for entry/dashboard |
| `GITHUB_TOKEN` | Fine-grained PAT (Contents: Read+Write, single repo) |
| `GITHUB_REPO` | Repository in `owner/repo` format |
| `GITHUB_BRANCH` | Target branch for commits (default: `main`) |
| `SITE_URL` | Base URL for customer page links (e.g., `https://myshop.pages.dev`) |

## Setup Script

`scripts/setup-cloudflare.sh` — interactive script that walks the shop owner through Cloudflare deployment setup, one question at a time. Designed for non-technical users, paired with `docs/cloudflare-setup.md` as a visual companion.

**Steps (in order):**

1. **Prerequisites check** — verify `wrangler` CLI is installed (prompt to install via `npm install -g wrangler` if missing)
2. **Cloudflare login** — run `wrangler login` if not already authenticated
3. **GitHub repository** — ask for `owner/repo` (e.g., `myname/camera-repair-store-inventory`), validate format
4. **GitHub token** — prompt to enter the fine-grained PAT (show instructions to create one with Contents: Read+Write on the single repo, reference `docs/cloudflare-setup.md` for screenshots)
5. **Branch** — ask for target branch, default to `main`
6. **Shop password** — ask the owner to set their admin password for the entry/dashboard
7. **Site URL** — ask for the Cloudflare Pages URL (or custom domain), default to `https://<project-name>.pages.dev`
8. **Create Cloudflare Pages project** — run `wrangler pages project create` if not already created
9. **Set secrets** — run `wrangler secret put` for `SHOP_PASSWORD`, `GITHUB_TOKEN`
10. **Set env vars** — configure `GITHUB_REPO`, `GITHUB_BRANCH`, `SITE_URL` via wrangler
11. **Run initial build + deploy** — run `./scripts/build.sh` and `wrangler pages deploy web/`
12. **Verify** — open the deployed URL and confirm access

Each step shows a clear prompt in Traditional Chinese with English technical terms. On error, the script explains what went wrong and how to fix it, referencing the relevant section of `docs/cloudflare-setup.md`.

## Rebuild Latency

After a create/update mutation, the GitHub commit triggers a Cloudflare Pages rebuild. This typically takes 30 seconds to a few minutes. During this window, the dashboard and item data are stale.

**Expected UX:**
- After form submit, the entry page shows a success message: "儲存成功，頁面資料將在數分鐘內更新" (Saved successfully, page data will update in a few minutes)
- The entry form resets (create) or stays on the current item (update) — no redirect to dashboard
- The shop owner understands that dashboard/search data reflects the last build, not real-time state

## Deliverables

- `functions/` — Cloudflare Pages Functions (middleware, API, customer gate)
- `scripts/build.sh` — build orchestrator
- `scripts/migrate-directory.sh` — one-time migration script (flat → YYYY/MM/ nesting)
- `scripts/generate-customer-pages.sh` — customer page generator
- `scripts/generate-manifest.sh` — published items manifest generator
- Updated `.gitignore` — exclude build-generated `web/_data/` and `web/customer/`
- `wrangler.toml` — Cloudflare Pages configuration
- `docs/cloud-architecture.md` — reusable reference for route-based Pages Functions architecture
- `scripts/setup-cloudflare.sh` — interactive setup script, walks through configuration one question at a time (see below)
- `docs/cloudflare-setup.md` — step-by-step guide for non-technical users, companion to `setup-cloudflare.sh` (includes GitHub token creation with minimum scope)
- Updated `CLAUDE.md` — local dev vs production context, hook architecture clarification
- Updated `README.md` — project overview with deployment info
- Updated `scripts/create-item.sh` — new directory structure (`YYYY/MM/`)
- Updated `scripts/update-item.sh` — `page_password` field handling, clear on delivered
- Updated `scripts/parse-item.sh` — validate new `page_password` field
- Updated `scripts/server.py` — scan nested `YYYY/MM/` directories for local dev
- Updated `web/entry.html` + `entry.js` — publish UI, static data fetching, Worker API calls
- Updated `docs/format.md` — document `page_password` field and `YYYY/MM/` directory layout
