# Camera Repair Shop Inventory System — Design Spec

## Overview

A file-based inventory system for a camera repair shop that tracks repair items through their lifecycle. The system uses structured Markdown files as the source of truth, shell scripts for data operations, and a local Python HTTP server for the web interface. All UI text is in Traditional Chinese.

## Data Model

### Repair Item Directory

Each repair item is a directory under `data/repairs/`:

```
data/
  repairs/
    CAM-20260322-EOSR5-001/
      item.md          # structured Markdown — source of truth
      logs/            # arbitrary files: photos, receipts, notes, etc.
    LENS-20260322-SEL2470GM-001/
      item.md
      logs/
```

### Item ID Format

`{TYPE}-{YYYYMMDD}-{MODEL}-{NNN}`

- **TYPE**: item category prefix
  - `CAM` — Camera (相機)
  - `LENS` — Lens (鏡頭)
  - `ACCE` — Accessory (配件)
  - `OTH` — Other (其他)
- **YYYYMMDD**: received date
- **MODEL**: model name with spaces and special characters stripped (e.g. `EOS R5` → `EOSR5`, `SEL 24-70 GM` → `SEL2470GM`). Entered manually by the shop.
- **NNN**: zero-padded daily sequence number. `create-item.sh` determines the next number by scanning `data/repairs/` for existing directories matching the same type+date+model prefix and incrementing.

### item.md Structure

YAML frontmatter for machine-parseable fields, Markdown body for structured content:

```markdown
---
id: CAM-20260322-EOSR5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345678"
status: in_progress
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

觀景窗有霧氣，快門異音

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
| 2026-03-22 | 3000 | 初步估價 |
| 2026-03-25 | 4500 | 需更換快門組件 |
```

**Frontmatter fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | yes | Auto-generated item ID |
| category | enum | yes | `camera`, `lens`, `accessory`, `misc` |
| brand | string | yes | Manufacturer name |
| model | string | yes | Model name (original, with spaces) |
| serial_number | string | yes | Serial number |
| status | enum | yes | Current repair status |
| owner_name | string | yes | Customer name |
| owner_contact | string | yes | Free-text contact (phone, IG, FB, etc.) |
| received_date | date | yes | Date item was received (YYYY-MM-DD) |
| delivered_date | date | no | Date item was delivered (YYYY-MM-DD) |

**Body sections** (parsed by heading name):

- `# 維修描述` — free-text repair description
- `# 費用紀錄` — Markdown table with columns: 日期, 金額, 說明

If frontmatter fields are missing or body sections are malformed, the parser exits with a clear error message identifying the specific problem and item.

### Status Lifecycle

Normal flow:

```
not_started → in_progress → testing → done → delivered
```

`ice_box` is an intentional hold state — any active status can move to `ice_box` and back. No strict transition enforcement; the UI shows contextual options.

New items are created with status `not_started`. Setting status to `delivered` automatically sets `delivered_date`.

**Status values:** `not_started`, `in_progress`, `testing`, `done`, `delivered`, `ice_box`

### Owner Registry

`data/owners.json` — an auto-maintained list of `{name, contact}` pairs, deduplicated. Updated by a hook script (`update-owners.sh`) that runs after every item create/update. Used for autocomplete on the entry page.

### Logs Folder

`logs/` within each item directory is an unmanaged bucket. The shop drops files in directly via Finder. The system provides a button to open this folder but does not parse or index its contents.

## System Architecture

### Directory Layout

```
camera-repair-store-inventory/
  data/
    repairs/                   # repair item directories
    owners.json                # auto-maintained owner registry
  scripts/
    server.sh                  # one-command start (checks python3, runs server.py)
    server.py                  # Python HTTP server (stdlib only)
    create-item.sh             # creates new repair item (dir + item.md + logs/)
    update-item.sh             # updates existing item's item.md
    parse-item.sh              # shared parser/validator for item.md
    update-owners.sh           # hook: syncs owners.json after create/update
    generate-entry.sh          # generates entry/edit HTML page
    generate-dashboard.sh      # generates kanban dashboard HTML
  web/
    entry.html                 # generated: form for creating/editing items
    dashboard.html             # generated: kanban status board
    static/                    # CSS, JS assets
  docs/
    format.md                  # documents the item.md schema
```

### Server

Python standard library only (`http.server` with a custom handler). No Flask, no pip, no venv. `server.sh` simply runs `python3 scripts/server.py`. Works on any Mac out of the box.

**Responsibilities:**

- Serve static files from `web/`
- POST `/api/create` — calls `create-item.sh`
- POST `/api/update` — calls `update-item.sh`
- POST `/api/deliver` — calls `update-item.sh` to set status=delivered
- GET `/api/open-logs/<id>` — runs `open` to launch Finder on the item's logs folder
- GET `/api/owners` — returns `data/owners.json` for autocomplete
- GET `/api/items` — returns all items as JSON for entry page search (frontmatter fields only, no body sections)

**`server.sh` behavior:**

1. Check Python 3 is available (macOS ships with it)
2. Start the server via `python3 scripts/server.py`
3. Clear error messages if anything fails (no Python 3, port in use, etc.)

### Data Flow

```
Browser form submit
  → POST /api/create or /api/update
  → server.py calls create-item.sh or update-item.sh
  → script writes/updates item.md
  → script calls update-owners.sh (syncs owners.json)
  → script calls generate-dashboard.sh (regenerates dashboard HTML)
  → server responds with success/error
```

### Parse & Validate

`parse-item.sh` is the single source of truth for reading `item.md`. Every script that reads an item goes through it. On parse failure, it exits with:

```
ERROR: item.md parse failed — missing required field 'serial_number' in CAM-20260322-EOSR5-001
```

## Web Interfaces

### Entry Page (建立/編輯維修單)

A single HTML form serving both create and edit modes.

**Search bar** at the top: type to filter existing items by ID, model, or owner name. Select an item → form fills in edit mode. Data loaded as JSON from `/api/items` on page open. Client-side filtering (under 30 active items).

**Create mode** — fields:

- Category (dropdown: 相機/鏡頭/配件/其他 — determines type prefix)
- Brand (text)
- Model (text — auto-stripped for ID generation)
- Serial number (text)
- Owner name (text, with autocomplete from owners.json)
- Owner contact (text, with autocomplete from owners.json)
- 維修描述 (textarea)
- Initial cost estimate (optional: amount + note)

On submit → `create-item.sh` generates the ID, creates directory + item.md + logs/, sets status to `not_started`.

**Edit mode** — all create fields plus:

- Status (dropdown with contextual options)
- Add cost entry (amount + note — appends row to cost table)
- Delivered date (auto-set when marking as delivered)
- "開啟維修記錄資料夾" button — opens the item's logs/ folder in Finder

On submit → `update-item.sh` rewrites item.md.

**Owner autocomplete**: selecting an existing owner fills both name and contact fields.

### Dashboard (維修進度看板)

Kanban board layout with columns per active status.

**Columns (left to right):**

- 未開始 (not_started)
- 進行中 (in_progress)
- 測試中 (testing)
- 完成・待取件 (done — awaiting pickup)

**Separate sections:**

- 冰箱 (ice_box) — collapsed by default
- 已交付 (delivered) — hidden from active view

**Card contents:**

- Item ID
- Model name
- Owner name
- Days since received

**Card interaction:** Click a card → navigate to entry page in edit mode for that item.

**Regeneration:** Dashboard HTML is regenerated after every data mutation, so it's always current when loaded.

## UI Language

- All interface text: Traditional Chinese
- Script output and error messages: English

## Technology Stack

- **Data store:** Structured Markdown files (YAML frontmatter + Markdown body)
- **Server:** Python 3 standard library (`http.server`)
- **Data scripts:** Bash
- **Frontend:** Vanilla HTML/CSS/JS — no build step, no framework
- **OS requirement:** macOS (for `open` command in Finder integration)
