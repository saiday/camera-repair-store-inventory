# Batch Update API Design

## Problem

Each `/api/update` call on Cloudflare creates a separate GitHub API commit. When batch-moving items on the kanban dashboard, N items produce N commits, triggering N Cloudflare Pages rebuilds. This is wasteful and slow.

Locally, the server runs hooks (update-owners, generate-dashboard) after each individual update — also redundant during batch operations.

## Solution

Add a `POST /api/batch-update` endpoint that applies multiple item updates in a single operation: one GitHub commit on Cloudflare, one hook invocation locally.

## Request / Response

**Request:**
```json
POST /api/batch-update
{
  "updates": [
    { "id": "CAM-20260305-FM-001", "status": "done" },
    { "id": "LENS-20260309-G-Rokkor-2835-001", "status": "in_progress", "owner_name": "田中" }
  ]
}
```

Each entry supports the same fields as `/api/update`: `status`, `owner_name`, `owner_contact`, `brand`, `serial_number`, `description`, `page_password`, `delivered_date`, `cost_amount`, `cost_note`, `cost_date`.

**Validation:**
- `updates` must be a non-empty array, max 50 items.
- Empty array or missing `updates` → 400.
- Duplicate IDs in the same batch → 400 (reject; caller should deduplicate).

**Success response (HTTP 200):**
```json
{ "ok": true, "ids": ["CAM-20260305-FM-001", "LENS-20260309-G-Rokkor-2835-001"] }
```

**Partial failure response (HTTP 200):**
```json
{ "ok": false, "error": "Some items failed", "succeeded": ["LENS-20260309-G-Rokkor-2835-001"], "failed": ["CAM-20260305-FM-001"] }
```
Partial failure commits the succeeded items and reports both lists. If all items fail to read, return 400.

## Cloudflare Worker: `functions/api/batch-update.js`

### Item Path Resolution (pre-existing bug fix)

The existing `findItemPath` in `update.js` hardcodes a flat path (`data/repairs/{id}/item.md`), but `create.js` writes to the nested `YYYY/MM/` layout. This is a pre-existing bug.

The shared helpers must resolve paths correctly. Item IDs embed the date: `CAM-20260305-FM-001` → date `20260305` → `data/repairs/2026/03/CAM-20260305-FM-001/item.md`. The helper extracts YYYY and MM from the ID's date segment (always the second hyphen-delimited part) to construct the nested path.

```javascript
function findItemPath(itemId) {
  const parts = itemId.split('-');
  const dateStr = parts[1]; // "20260305"
  const year = dateStr.substring(0, 4);
  const month = dateStr.substring(4, 6);
  return `data/repairs/${year}/${month}/${itemId}/item.md`;
}
```

This fix applies to both `update.js` and `batch-update.js` via the shared module.

### Field Update Logic

Extract `replaceField` and field-application logic from `functions/api/update.js` into `functions/api/_update-helpers.js` (prefixed with `_` so Cloudflare doesn't route it). Both `update.js` and `batch-update.js` import from this shared module.

Shared module exports: `githubApi(env, path, options)`, `findItemPath(itemId)`, `replaceField(content, field, value)`, `applyUpdates(content, data)`.

### Git Tree API Flow

Instead of N individual commits via the Contents API, use the lower-level Git API to create a single commit:

1. **Get current ref** — `GET /repos/{owner}/{repo}/git/ref/heads/{branch}` to get HEAD commit SHA. Do this first to establish a consistent base.
2. **Get HEAD commit's tree** — `GET /repos/{owner}/{repo}/git/commits/{sha}` to get the tree SHA.
3. **Read all item files** — parallel `GET /repos/{owner}/{repo}/contents/{path}?ref={branch}` for each item, using the branch ref from step 1. Collect current content. Skip items that 404.
4. **Apply field updates** — run shared update logic on each file's content in memory.
5. **Create tree** — `POST /repos/{owner}/{repo}/git/trees` with `base_tree` = step 2's tree SHA. Tree entries use inline `content` (no need for separate blob creation for small markdown files).
6. **Create commit** — `POST /repos/{owner}/{repo}/git/commits` with the new tree SHA and parent = step 1's commit SHA. Message: `update: ITEM-1, ITEM-2, ITEM-3`.
7. **Update ref** — `PATCH /repos/{owner}/{repo}/git/ref/heads/{branch}` to point to the new commit. Uses `force: false` — fails safely if the branch moved since step 1.

### Authentication

The existing `functions/_middleware.js` covers all `/api/*` routes. No additional auth needed in the batch endpoint.

### Error Handling

- Items not found in step 3 are skipped. If some items succeed and some don't, commit the successful ones and return partial failure response.
- If all items fail to read, return 400 with list of failed IDs.
- If Git API calls (steps 5-7) fail, return 500 with the GitHub API error.
- If ref update fails due to concurrent push (step 7), return 409. Dashboard shows an error; user can retry manually.

## Local Server: `server.py`

Add route `/api/batch-update` in `do_POST` and handler `_handle_batch_update(self, data)`:

1. Validate `data["updates"]`: non-empty list, max 50 items, no duplicate IDs.
2. Loop through each update entry, call `update-item.sh --no-hooks` for each.
3. Track succeeded/failed IDs.
4. Run hooks **once** at the end via `_run_hooks()`. Note: `_run_hooks` takes `item_id` but doesn't use it — pass any succeeded ID.
5. Return the same response format as the Cloudflare version.

## Dashboard JS Changes

In `web/static/dashboard.js`, replace the sequential `/api/update` loop with a single `POST /api/batch-update`:

```javascript
fetch('/api/batch-update', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    updates: ids.map(function(id) { return { id: id, status: status }; })
  })
})
```

On success or partial success: show environment-aware success toast (already implemented), then reload.
On error (network/500/409): `alert('批次更新失敗，請重試')`, then reload.

## Files Changed

| File | Change |
|------|--------|
| `functions/api/_update-helpers.js` | New — shared `githubApi`, `findItemPath`, `replaceField`, `applyUpdates` |
| `functions/api/update.js` | Refactor to import from `_update-helpers.js` |
| `functions/api/batch-update.js` | New — batch update endpoint using Git Tree API |
| `scripts/server.py` | Add `/api/batch-update` route and `_handle_batch_update` handler |
| `web/static/dashboard.js` | Replace sequential update loop with single batch-update call |
| `tests/test_server.sh` | Add batch-update integration test |
