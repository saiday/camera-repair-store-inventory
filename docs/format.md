# item.md Format Reference

This document describes the schema for `item.md` files used by the camera repair shop inventory system. Each repair item lives in its own directory under `data/repairs/` and contains one `item.md` as the source of truth.

---

## File Structure

An `item.md` consists of two parts:

1. **YAML frontmatter** — machine-parseable key/value fields between `---` delimiters
2. **Markdown body** — two required sections identified by heading name

```
---
<frontmatter fields>
---

# 維修描述

<free-text repair description>

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
<cost rows, one per line>
```

---

## Frontmatter Fields

| Field | Type | Required | Allowed Values |
|---|---|---|---|
| `id` | string | yes | Auto-generated item ID (see ID Format below) |
| `category` | enum | yes | `camera`, `lens`, `accessory`, `misc` |
| `brand` | string | yes | Manufacturer name, free text |
| `model` | string | yes | Model name, free text (original with spaces) |
| `serial_number` | string | yes | Serial number — always quoted with double quotes |
| `status` | enum | yes | See Status Values below |
| `owner_name` | string | yes | Customer name, free text |
| `owner_contact` | string | yes | Free text: phone, IG, FB, etc. |
| `received_date` | date | yes | ISO date: `YYYY-MM-DD` |
| `delivered_date` | date | no | ISO date: `YYYY-MM-DD` — empty until item is delivered |
| `page_password` | string | no | Password to share customer page; empty unless page is published |

### Notes

- `serial_number` is always written with surrounding double quotes (e.g., `serial_number: "012345678"`) to prevent YAML parsers from interpreting numeric-looking values as integers.
- `delivered_date` is an empty YAML field (i.e., `delivered_date:` with no value) until the item status becomes `delivered`, at which point the date is set automatically.
- All other string fields are written unquoted.

---

## Body Sections

The Markdown body must contain exactly these two level-1 headings, in order:

### `# 維修描述`

Free text describing the repair. May span multiple lines. No structural constraints.

### `# 費用紀錄`

A Markdown table with three columns in this exact order:

| Column | Content |
|---|---|
| 日期 | Date of the cost entry, ISO format `YYYY-MM-DD` |
| 金額 | Amount (integer, no currency symbol) |
| 說明 | Description or reason for the cost |

The table header and separator row are always written as:

```
| 日期 | 金額 | 說明 |
|------|------|------|
```

Cost rows are appended (never edited in place). Each new cost entry adds a row to the bottom of the table. The table may have zero rows if no cost has been recorded yet.

---

## ID Format

```
{TYPE}-{YYYYMMDD}-{MODEL}-{NNN}
```

### Components

| Part | Description |
|---|---|
| `TYPE` | Category prefix (see table below) |
| `YYYYMMDD` | Received date, compact format (dashes removed from `received_date`) |
| `MODEL` | Normalized model name (see normalization rules below) |
| `NNN` | Three-digit zero-padded daily sequence number, starting at `001` |

### Category Prefixes

| Category value | Prefix |
|---|---|
| `camera` | `CAM` |
| `lens` | `LENS` |
| `accessory` | `ACCE` |
| `misc` | `OTH` |

### Model Normalization Rules

Applied to the raw model name entered by the shop to produce the `MODEL` segment of the ID:

1. Spaces are replaced with dashes (`-`)
2. All characters that are not alphanumeric ASCII or dashes are removed
3. Original casing is preserved

Examples:

| Raw model | Normalized |
|---|---|
| `EOS R5` | `EOS-R5` |
| `SEL 24-70 GM` | `SEL-24-70-GM` |
| `Nikon Zfc` | `Nikon-Zfc` |
| `α7 IV` | `7-IV` *(non-ASCII α removed, space becomes dash)* |

### Sequence Number

`create-item.sh` determines the next sequence number by scanning `data/repairs/` for existing directories whose names begin with `{TYPE}-{YYYYMMDD}-{MODEL}-` and incrementing the highest found. If no match exists, the number starts at `001`.

The sequence is per type+date+model combination, not global. Two different models on the same day each get their own `001`.

---

## Status Values and Lifecycle

### Values

| Value | Meaning (Chinese label) |
|---|---|
| `not_started` | 未開始 — item received, repair not yet started |
| `in_progress` | 進行中 — repair actively underway |
| `testing` | 測試中 — repair done, under functional testing |
| `done` | 完成・待取件 — ready for customer pickup |
| `delivered` | 已交付 — returned to customer |
| `ice_box` | 冰箱 — intentional hold (waiting for parts, owner decision, etc.) |

### Normal Flow

```
not_started → in_progress → testing → done → delivered
```

### Ice Box

`ice_box` is a hold state that can be entered from any active status and exited back to any active status. There is no strict transition enforcement — the UI shows contextual options.

### Delivered

When status is set to `delivered`, `delivered_date` is automatically set to the current date by `update-item.sh`. Delivered items are hidden from the active kanban view.

### Initial Status

New items are always created with `status: not_started`.

---

## Complete Example

```markdown
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
page_password: "customer123"
---

# 維修描述

觀景窗有霧氣，快門異音。客戶反映問題從上個月開始出現。

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
| 2026-03-22 | 3000 | 初步估價 |
| 2026-03-25 | 4500 | 需更換快門組件 |
```

---

## Validation

`scripts/parse-item.sh` is the authoritative parser. It validates:

- Frontmatter delimiters (`---`) are present
- All required fields are non-empty
- `status` is one of the six valid values
- `category` is one of the four valid values
- Both body sections (`# 維修描述` and `# 費用紀錄`) are present

On failure it prints a message to stderr and exits with code 1:

```
ERROR: item.md parse failed — missing required field 'serial_number' in CAM-20260322-EOS-R5-001
ERROR: item.md parse failed — invalid status 'pending' in CAM-20260322-EOS-R5-001 (valid: not_started in_progress testing done delivered ice_box)
ERROR: item.md parse failed — missing section "# 費用紀錄" in CAM-20260322-EOS-R5-001
```

On success it outputs a JSON object with all frontmatter fields to stdout.

---

## Directory Layout

Items are organized by year and month based on `received_date`:

```
data/repairs/
  2026/
    03/
      CAM-20260322-EOS-R5-001/
        item.md      # this file — source of truth
        logs/        # unmanaged bucket: photos, receipts, notes
      LENS-20260315-SEL-24-70-GM-001/
        item.md
        logs/
    04/
      ...
```

Each item occupies one directory. The `logs/` directory is not parsed or indexed. The shop drops files in it directly via Finder. The system provides a button to open this folder but ignores its contents.
