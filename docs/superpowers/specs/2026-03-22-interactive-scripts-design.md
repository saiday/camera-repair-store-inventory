# Interactive Scripts & Script-Based Hooks

## Summary

Add interactive REPL mode to `create-item.sh` and `update-item.sh`, move hook logic (`update-owners.sh`, `generate-dashboard.sh`) from the server into the mutation scripts, and make brand searchable in both the CLI and web UI.

## Motivation

- Running scripts from the CLI currently requires memorizing flag names and typing long commands
- Hook logic lives in `server.py._run_hooks`, meaning CLI usage silently skips owner/dashboard sync
- Brand is not searchable in the update flow or the web entry page

## Interactive Mode Detection

Both `create-item.sh` and `update-item.sh` detect interactive mode when:
- No arguments are passed (`$# -eq 0`)
- AND stdin is a TTY (`[ -t 0 ]`)

Otherwise, they run in non-interactive flag mode (unchanged behavior for the server and scripted usage).

## `create-item.sh` Interactive Flow

Prompts for each required field sequentially:

```
$ scripts/create-item.sh
Category (camera/lens/accessory/misc): camera
Brand: Nikon
Model: FM
Serial: 8123456
Owner: 高先生
Contact: 0911-234-567
Description: 測光表檢修
Date [2026-03-22]:
✓ Created CAM-20260322-FM-001
```

- `Date` defaults to today (`date +%Y-%m-%d`) if left blank
- `data-dir` defaults to `../data` relative to the script directory (already in place)
- All existing validation (category enum, required fields) still applies after input collection
- On validation failure, print the error and re-prompt for the invalid field

## `update-item.sh` Interactive Flow

### Item selection

```
$ scripts/update-item.sh
Search: nikon
  1) CAM-20260305-FM-001 — Nikon FM (高先生)
  2) CAM-20260318-S3-2000-001 — Nikon S3 2000 (王先生)
  3) LENS-20260321-13535-001 — Nikon 135/3.5 (張小姐)
Select [1]: 1
```

- Search input is matched case-insensitively against: brand, model, owner name, and item ID
- If the search matches exactly one item, skip the selection prompt
- If the input matches a full item ID pattern directly, use it without searching
- Search is implemented by scanning `data/repairs/*/item.md` via `parse-item.sh`

### Field update

```
Current: status=not_started, brand=Nikon, model=FM, owner=高先生
New status (not_started/in_progress/testing/done/delivered/ice_box) [not_started]: in_progress
Add cost? (y/N): y
  Amount: 500
  Note: 初步檢查
✓ Updated CAM-20260305-FM-001
```

- Shows current values as context
- Each field prompt shows the current value as default (press Enter to keep)
- Only status and cost are prompted (these are the most common update operations)
- For other fields (owner, description, brand, serial), the existing flag interface remains the way to update them

## Hooks: Script-Based, Not Server-Based

### Change

- `create-item.sh` and `update-item.sh` call `update-owners.sh` and `generate-dashboard.sh` after a successful mutation
- Hooks run in the background (`&`) so they don't block the script's output
- `server.py`: remove `_run_hooks` method and its call sites — the server no longer manages hooks since the underlying scripts handle it

### `--no-hooks` flag

Both scripts accept `--no-hooks` to skip hook execution. Use case: batch imports where you want to run hooks once at the end.

```bash
# Batch import — skip per-item hooks
for ...; do
  scripts/create-item.sh --no-hooks --category ... --brand ...
done
# Run hooks once at the end
scripts/update-owners.sh
scripts/generate-dashboard.sh
```

## Brand Searchable in Web UI

The entry page (`entry.html`) search functionality will match against the `brand` field in addition to whatever fields it currently searches (model, owner, ID). This is a frontend-only change — the `/api/items` endpoint already returns brand in the JSON payload.

## Files Changed

| File | Change |
|------|--------|
| `scripts/create-item.sh` | Add interactive mode, add hook calls, add `--no-hooks` flag |
| `scripts/update-item.sh` | Add interactive mode with search, add hook calls, add `--no-hooks` flag |
| `scripts/server.py` | Remove `_run_hooks` method and its call sites |
| `web/static/entry.js` (or equivalent) | Add brand to search matching |
