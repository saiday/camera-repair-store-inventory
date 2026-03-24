# Batch Update API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `POST /api/batch-update` endpoint that bundles multiple item updates into a single GitHub commit (Cloudflare) or a single hook invocation (local), replacing the current N-commits-per-batch-move behavior.

**Architecture:** Extract shared update logic from `functions/api/update.js` into a helpers module. Create `batch-update.js` that uses the Git Tree API for atomic multi-file commits. Add matching local server handler. Update dashboard JS to call the new endpoint.

**Tech Stack:** Cloudflare Pages Functions (JS), Python 3 stdlib, vanilla JS, bash tests.

**Spec:** `docs/superpowers/specs/2026-03-24-batch-update-design.md`

---

### Task 1: Extract shared helpers from `functions/api/update.js`

**Context:** `update.js` currently defines three local functions (`githubApi`, `findItemPath`, `replaceField`) and applies field updates inline in the `onRequest` handler (the block between `// Apply field updates` and `// Commit`). These need to be shared with the new `batch-update.js`. Also fixes a pre-existing bug: `findItemPath` returns a flat path (`data/repairs/${itemId}/item.md`) but items live in nested `YYYY/MM/` directories.

**Files:**
- Create: `functions/api/_update-helpers.js`
- Modify: `functions/api/update.js`

- [ ] **Step 1: Create `functions/api/_update-helpers.js`**

The `_` prefix prevents Cloudflare from routing this file as an endpoint. Export four functions:

```javascript
// functions/api/_update-helpers.js — Shared helpers for update endpoints

export function githubApi(env, path, options = {}) {
  return fetch(`https://api.github.com/repos/${env.GITHUB_REPO}/${path}`, {
    ...options,
    headers: {
      'Authorization': `Bearer ${env.GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
      'User-Agent': 'camera-repair-store-inventory',
      ...options.headers,
    },
  });
}

export function findItemPath(itemId) {
  const parts = itemId.split('-');
  const dateStr = parts[1]; // e.g. "20260305"
  const year = dateStr.substring(0, 4);
  const month = dateStr.substring(4, 6);
  return `data/repairs/${year}/${month}/${itemId}/item.md`;
}

export function replaceField(content, field, newValue) {
  const regex = new RegExp(`^${field}:.*$`, 'm');
  if (regex.test(content)) {
    return content.replace(regex, `${field}: ${newValue}`);
  }
  const closingIdx = content.indexOf('\n---', 3);
  if (closingIdx !== -1) {
    return content.slice(0, closingIdx) + `\n${field}: ${newValue}` + content.slice(closingIdx);
  }
  return content;
}

export function applyUpdates(content, data) {
  const fields = ['status', 'owner_name', 'owner_contact', 'brand', 'description'];
  for (const field of fields) {
    if (data[field] !== undefined && data[field] !== '') {
      if (field === 'description') {
        content = content.replace(
          /(# 維修描述\n\n)[\s\S]*?(\n# 費用紀錄)/,
          `$1${data.description}\n$2`
        );
      } else {
        content = replaceField(content, field, data[field]);
      }
    }
  }

  if (data.serial_number) {
    content = replaceField(content, 'serial_number', `"${data.serial_number}"`);
  }
  if (data.page_password !== undefined) {
    content = replaceField(content, 'page_password', data.page_password);
  }
  if (data.delivered_date) {
    content = replaceField(content, 'delivered_date', data.delivered_date);
  }
  if (data.status === 'delivered') {
    content = replaceField(content, 'page_password', '');
    if (!data.delivered_date) {
      content = replaceField(content, 'delivered_date', new Date().toISOString().split('T')[0]);
    }
  }
  if (data.cost_amount && data.cost_note) {
    const costDate = data.cost_date || new Date().toISOString().split('T')[0];
    const costLine = `| ${costDate} | ${data.cost_amount} | ${data.cost_note} |`;
    content = content.trimEnd() + '\n' + costLine + '\n';
  }

  return content;
}
```

- [ ] **Step 2: Refactor `functions/api/update.js` to import from helpers**

Replace the local function definitions with imports and use `applyUpdates`. The file should become:

```javascript
// functions/api/update.js — Update item via GitHub API commit
import { githubApi, findItemPath, applyUpdates } from './_update-helpers.js';

export async function onRequest(context) {
  const { request, env } = context;
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const data = await request.json();
  const branch = env.GITHUB_BRANCH || 'main';
  const itemId = data.id;
  const filePath = findItemPath(itemId);

  // Read current file
  const getRes = await githubApi(env, `contents/${filePath}?ref=${branch}`);
  if (!getRes.ok) {
    return Response.json({ error: 'Item not found' }, { status: 404 });
  }
  const fileData = await getRes.json();
  // GitHub API returns base64 with embedded newlines; strip before decoding
  let content = decodeURIComponent(escape(atob(fileData.content.replace(/\n/g, ''))));
  const sha = fileData.sha;

  // Apply field updates
  content = applyUpdates(content, data);

  // Commit
  const updateRes = await githubApi(env, `contents/${filePath}`, {
    method: 'PUT',
    body: JSON.stringify({
      message: `update: ${itemId}`,
      content: btoa(unescape(encodeURIComponent(content))),
      sha,
      branch,
    }),
  });

  if (updateRes.ok) {
    return Response.json({ ok: true, id: itemId });
  }
  const err = await updateRes.text();
  return Response.json({ error: `GitHub API error: ${err}` }, { status: 500 });
}
```

- [ ] **Step 3: Verify the refactored `update.js` preserves all behavior**

This is a Cloudflare Worker — there's no local test runner. Read the original `functions/api/update.js` (before your edits — use `git show HEAD:functions/api/update.js`) and diff against the new version plus helpers. Confirm:
- Every function from the original (`githubApi`, `findItemPath`, `replaceField`) exists in `_update-helpers.js`
- All field-update logic from the original `onRequest` handler (the block applying status, owner_name, serial_number, page_password, delivered_date, cost entries) is captured in `applyUpdates`
- The import path is correct (relative `./_update-helpers.js`)
- The refactored `update.js` produces identical behavior for all inputs

- [ ] **Step 4: Commit**

```bash
git add functions/api/_update-helpers.js functions/api/update.js
git commit -m "refactor: extract shared update helpers from update.js

Moves githubApi, findItemPath, replaceField, and field-application
logic into _update-helpers.js. Fixes findItemPath to use nested
YYYY/MM/ directory layout instead of flat path."
```

---

### Task 2: Create `functions/api/batch-update.js` (Cloudflare Worker)

**Context:** This is the core of the feature. Uses the Git Tree API to create a single commit containing all item changes. Imports shared helpers from Task 1.

**Files:**
- Create: `functions/api/batch-update.js`

**Reference:** GitHub Git Tree API docs. The flow is: get HEAD ref → get HEAD tree → read item files → apply updates → create new tree → create commit → update ref.

- [ ] **Step 1: Create `functions/api/batch-update.js`**

```javascript
// functions/api/batch-update.js — Batch update items via single GitHub API commit
import { githubApi, findItemPath, applyUpdates } from './_update-helpers.js';

const MAX_BATCH_SIZE = 50;

function decodeContent(base64) {
  // GitHub API returns base64 with embedded newlines; strip before decoding
  return decodeURIComponent(escape(atob(base64.replace(/\n/g, ''))));
}

function encodeContent(text) {
  return btoa(unescape(encodeURIComponent(text)));
}

export async function onRequest(context) {
  const { request, env } = context;
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const body = await request.json();
  const updates = body.updates;

  // --- Validation ---
  if (!Array.isArray(updates) || updates.length === 0) {
    return Response.json({ error: 'updates must be a non-empty array' }, { status: 400 });
  }
  if (updates.length > MAX_BATCH_SIZE) {
    return Response.json({ error: `Too many updates (max ${MAX_BATCH_SIZE})` }, { status: 400 });
  }
  const ids = updates.map(u => u.id);
  if (new Set(ids).size !== ids.length) {
    return Response.json({ error: 'Duplicate IDs in batch' }, { status: 400 });
  }

  const branch = env.GITHUB_BRANCH || 'main';

  // --- Step 1: Get current HEAD ref ---
  const refRes = await githubApi(env, `git/ref/heads/${branch}`);
  if (!refRes.ok) {
    return Response.json({ error: 'Failed to get branch ref' }, { status: 500 });
  }
  const refData = await refRes.json();
  const headSha = refData.object.sha;

  // --- Step 2: Get HEAD commit's tree SHA ---
  const commitRes = await githubApi(env, `git/commits/${headSha}`);
  if (!commitRes.ok) {
    return Response.json({ error: 'Failed to get HEAD commit' }, { status: 500 });
  }
  const commitData = await commitRes.json();
  const baseTreeSha = commitData.tree.sha;

  // --- Step 3: Read all item files in parallel ---
  const readResults = await Promise.all(
    updates.map(async (entry) => {
      const filePath = findItemPath(entry.id);
      const res = await githubApi(env, `contents/${filePath}?ref=${branch}`);
      if (!res.ok) {
        return { id: entry.id, error: true };
      }
      const fileData = await res.json();
      return { id: entry.id, filePath, content: decodeContent(fileData.content), entry };
    })
  );

  const succeeded = readResults.filter(r => !r.error);
  const failed = readResults.filter(r => r.error).map(r => r.id);

  if (succeeded.length === 0) {
    return Response.json({ error: 'All items failed to read', failed }, { status: 400 });
  }

  // --- Step 4: Apply field updates ---
  const treeEntries = succeeded.map(item => {
    const updatedContent = applyUpdates(item.content, item.entry);
    return {
      path: item.filePath,
      mode: '100644',
      type: 'blob',
      content: updatedContent,
    };
  });

  // --- Step 5: Create tree ---
  const treeRes = await githubApi(env, 'git/trees', {
    method: 'POST',
    body: JSON.stringify({ base_tree: baseTreeSha, tree: treeEntries }),
  });
  if (!treeRes.ok) {
    const err = await treeRes.text();
    return Response.json({ error: `Failed to create tree: ${err}` }, { status: 500 });
  }
  const treeData = await treeRes.json();

  // --- Step 6: Create commit ---
  const succeededIds = succeeded.map(s => s.id);
  const message = `update: ${succeededIds.join(', ')}`;
  const newCommitRes = await githubApi(env, 'git/commits', {
    method: 'POST',
    body: JSON.stringify({
      message,
      tree: treeData.sha,
      parents: [headSha],
    }),
  });
  if (!newCommitRes.ok) {
    const err = await newCommitRes.text();
    return Response.json({ error: `Failed to create commit: ${err}` }, { status: 500 });
  }
  const newCommitData = await newCommitRes.json();

  // --- Step 7: Update ref ---
  const updateRefRes = await githubApi(env, `git/refs/heads/${branch}`, {
    method: 'PATCH',
    body: JSON.stringify({ sha: newCommitData.sha, force: false }),
  });
  if (!updateRefRes.ok) {
    return Response.json({ error: 'Concurrent update conflict, please retry' }, { status: 409 });
  }

  // --- Response ---
  if (failed.length > 0) {
    return Response.json({ ok: false, error: 'Some items failed', succeeded: succeededIds, failed });
  }
  return Response.json({ ok: true, ids: succeededIds });
}
```

- [ ] **Step 2: Read the file and verify correctness**

Check the complete file. Verify:
- Import path matches the helpers module from Task 1
- All 7 Git API steps from the spec are implemented in the correct order (ref first, then tree, read files, apply, create tree, commit, update ref)
- Validation: empty array, max 50, duplicate IDs
- Error responses match spec: 400, 409, 500
- Partial failure: commits succeeded items, reports both lists

- [ ] **Step 3: Commit**

```bash
git add functions/api/batch-update.js
git commit -m "feat: add batch-update Cloudflare worker endpoint

Uses Git Tree API to commit all item changes in a single commit,
preventing N rebuilds when batch-moving items on the dashboard."
```

---

### Task 3: Add `_handle_batch_update` to local server

**Context:** The local server (`scripts/server.py`) needs a matching `/api/batch-update` route. It loops through updates calling `update-item.sh --no-hooks` for each, then runs hooks once. The existing `_handle_update` method shows the pattern for calling update-item.sh. Key existing methods you'll reference: `_find_item_dir(item_id)` resolves an item ID to its directory path via glob search, `_send_json(status_code, data)` sends a JSON HTTP response, `_run_hooks(item_id)` runs `update-owners.sh` and `generate-dashboard.sh` (the `item_id` param is accepted but unused — hooks operate on `self.data_dir`).

**Files:**
- Modify: `scripts/server.py` (add route in `do_POST`, add handler method)
- Modify: `tests/test_server.sh` (add 3 new tests)

- [ ] **Step 1: Write the failing test in `tests/test_server.sh`**

Add the test function before the `# --- Run all tests ---` comment. The file structure is: test function definitions at the top, then a run section at the bottom that calls `run_test "label" function_name` for each test, ending with `print_results`.

```bash
# --- Test: POST /api/batch-update changes multiple item statuses ---
test_batch_update() {
  setup
  # Create two items
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test1" --date "2026-03-22" > /dev/null
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category lens --brand Canon --model "RF50" \
    --serial "002" --owner-name "王小明" --owner-contact "0912" \
    --description "Test2" --date "2026-03-22" > /dev/null
  start_server

  # Batch update both items
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": [
      {"id": "CAM-20260322-EOS-R5-001", "status": "in_progress"},
      {"id": "LENS-20260322-RF50-001", "status": "done"}
    ]}')"
  assert_contains "$response" '"ok"' "batch-update should return ok"
  assert_contains "$response" "CAM-20260322-EOS-R5-001" "response should list first item"
  assert_contains "$response" "LENS-20260322-RF50-001" "response should list second item"

  # Verify both items changed
  local raw1 raw2
  raw1="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$raw1" "status: in_progress" "first item status should be updated"
  raw2="$(curl -s "http://localhost:$TEST_PORT/api/item/LENS-20260322-RF50-001/raw")"
  assert_contains "$raw2" "status: done" "second item status should be updated"

  stop_server
  teardown
}
```

Also add to the run section (before the `print_results` call at the end of the file):

```bash
run_test "POST /api/batch-update" test_batch_update
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_server.sh`

Expected: The `POST /api/batch-update` test fails because the endpoint doesn't exist yet (server returns 404).

- [ ] **Step 3: Add validation test**

Add a test for validation (empty updates, duplicate IDs):

```bash
# --- Test: POST /api/batch-update validates input ---
test_batch_update_validation() {
  setup
  start_server

  # Empty updates array
  local response
  response="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": []}')"
  assert_eq "400" "$response" "empty updates should return 400"

  # Duplicate IDs
  response="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": [{"id": "X-001", "status": "done"}, {"id": "X-001", "status": "done"}]}')"
  assert_eq "400" "$response" "duplicate IDs should return 400"

  stop_server
  teardown
}
```

- [ ] **Step 3b: Add partial failure test**

```bash
# --- Test: POST /api/batch-update partial failure ---
test_batch_update_partial_failure() {
  setup
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "Test" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  start_server

  # One valid ID, one non-existent
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": [
      {"id": "CAM-20260322-EOS-R5-001", "status": "in_progress"},
      {"id": "NONEXISTENT-20260101-X-001", "status": "done"}
    ]}')"
  assert_contains "$response" '"succeeded"' "should report succeeded list"
  assert_contains "$response" '"failed"' "should report failed list"
  assert_contains "$response" "CAM-20260322-EOS-R5-001" "succeeded should contain valid item"

  # Verify the valid item was still updated
  local raw
  raw="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$raw" "status: in_progress" "valid item should still be updated"

  stop_server
  teardown
}
```

Also add to the run section (before `print_results`, after the `run_test` for `test_batch_update`):

```bash
run_test "POST /api/batch-update validation" test_batch_update_validation
run_test "POST /api/batch-update partial failure" test_batch_update_partial_failure
```

- [ ] **Step 4: Implement `_handle_batch_update` in `server.py`**

Read `scripts/server.py` and find the `do_POST` method. It has a chain of `if/elif` for routes: `/api/create`, `/api/update`, `/api/deliver`, then `else: 404`. Add the new route before the `else`:

```python
        elif path == '/api/batch-update':
            self._handle_batch_update(data)
```

Add the handler method as a new method on the `InventoryHandler` class. Place it after `_handle_deliver` and before `_run_hooks`:

```python
    def _handle_batch_update(self, data):
        """Batch update multiple items, running hooks only once."""
        updates = data.get('updates')
        if not isinstance(updates, list) or len(updates) == 0:
            self._send_json(400, {'error': 'updates must be a non-empty array'})
            return
        if len(updates) > 50:
            self._send_json(400, {'error': 'Too many updates (max 50)'})
            return
        ids = [u.get('id', '') for u in updates]
        if len(set(ids)) != len(ids):
            self._send_json(400, {'error': 'Duplicate IDs in batch'})
            return

        succeeded = []
        failed = []
        for entry in updates:
            item_id = entry.get('id', '')
            item_dir = self._find_item_dir(item_id)
            if item_dir is None or not os.path.isdir(item_dir):
                failed.append(item_id)
                continue

            cmd = [os.path.join(self.scripts_dir, 'update-item.sh'), '--no-hooks', '--item-dir', item_dir]

            field_map = {
                'status': '--status',
                'owner_name': '--owner-name',
                'owner_contact': '--owner-contact',
                'description': '--description',
                'brand': '--brand',
                'serial_number': '--serial',
                'page_password': '--page-password',
            }
            for field, flag in field_map.items():
                if entry.get(field) not in (None, ''):
                    cmd += [flag, str(entry[field])]

            if entry.get('cost_amount') and entry.get('cost_note'):
                cmd += [
                    '--cost-amount', str(entry['cost_amount']),
                    '--cost-note', entry['cost_note'],
                    '--cost-date', entry.get('cost_date', ''),
                ]

            if entry.get('delivered_date'):
                cmd += ['--delivered-date', entry['delivered_date']]

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                succeeded.append(item_id)
            else:
                failed.append(item_id)

        # Run hooks once — _run_hooks takes item_id but doesn't use it;
        # hooks regenerate all data from data_dir regardless of which item changed.
        if succeeded:
            self._run_hooks(succeeded[0])

        if not succeeded:
            self._send_json(400, {'error': 'All items failed', 'failed': failed})
        elif failed:
            self._send_json(200, {'ok': False, 'error': 'Some items failed', 'succeeded': succeeded, 'failed': failed})
        else:
            self._send_json(200, {'ok': True, 'ids': succeeded})
```

- [ ] **Step 5: Run all tests to verify they pass**

Run: `bash tests/test_server.sh`

Expected: All tests pass including both new batch-update tests.

- [ ] **Step 6: Commit**

```bash
git add scripts/server.py tests/test_server.sh
git commit -m "feat: add batch-update endpoint to local server

Loops through updates calling update-item.sh --no-hooks for each,
then runs hooks once at the end. Includes integration tests."
```

---

### Task 4: Update dashboard JS to use batch-update endpoint

**Context:** `web/static/dashboard.js` has two `document.addEventListener('click', ...)` blocks in the Selection Mode section. The first handles card selection (checks for `.card` target). The second handles status pill clicks (checks for `.status-pill` target) — it currently loops through `selectedIds` making sequential `fetch('/api/update', ...)` calls via a recursive `next()` function. Replace this second block with a single `/api/batch-update` call. The file also uses `selectMode` and `selectedIds` variables defined earlier in the file.

**Files:**
- Modify: `web/static/dashboard.js`

- [ ] **Step 1: Replace the sequential update loop with a single batch-update call**

Read `web/static/dashboard.js`. Find the second `document.addEventListener('click', ...)` block — the one that starts with `var pill = e.target.closest('.status-pill')` (or `const pill`). It contains a `function next()` that makes sequential `/api/update` calls. Replace this entire block (from `document.addEventListener('click', function(e) {` to its closing `});`) with:

```javascript
document.addEventListener('click', function(e) {
  var pill = e.target.closest('.status-pill');
  if (!pill || !selectMode) return;
  if (pill.classList.contains('disabled')) return;

  var status = pill.getAttribute('data-status');
  var label = pill.textContent;
  var count = selectedIds.length;

  if (!confirm('確定移動 ' + count + ' 件到 ' + label + '？')) return;

  var updates = selectedIds.map(function(id) {
    return { id: id, status: status };
  });

  fetch('/api/batch-update', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ updates: updates })
  }).then(function(res) {
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return res.json();
  }).then(function(data) {
    var isLocal = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
    var msg = '儲存成功';
    if (!isLocal) msg += '，頁面資料將在數分鐘內更新';
    if (data.failed && data.failed.length > 0) {
      msg += '\n（' + data.failed.length + ' 件失敗）';
    }
    alert(msg);
    location.reload();
  }).catch(function() {
    alert('批次更新失敗，請重試');
    location.reload();
  });
});
```

- [ ] **Step 2: Verify the change by reading the file**

Read `web/static/dashboard.js` and confirm:
- The old sequential `next()` loop is completely gone
- The new handler sends a single `/api/batch-update` POST
- Environment-aware toast is preserved
- Partial failure is reported to the user
- Error case shows Chinese error message and reloads

- [ ] **Step 3: Commit**

```bash
git add web/static/dashboard.js
git commit -m "feat: dashboard uses batch-update endpoint for kanban moves

Replaces sequential /api/update calls with single /api/batch-update,
reducing to one commit and one rebuild per batch operation."
```

---

### Task 5: End-to-end verification

**Context:** Run all tests to make sure nothing is broken across the full change set.

- [ ] **Step 1: Run all tests**

```bash
bash tests/test_generate_dashboard.sh && bash tests/test_server.sh
```

Expected: All tests pass (7 dashboard + 10 server = 17 total).

- [ ] **Step 2: Verify file structure**

Confirm the final set of changed/created files matches the spec:

```bash
git diff --stat HEAD~4..HEAD
```

Expected files:
- `functions/api/_update-helpers.js` (new)
- `functions/api/update.js` (modified)
- `functions/api/batch-update.js` (new)
- `scripts/server.py` (modified)
- `web/static/dashboard.js` (modified)
- `tests/test_server.sh` (modified)
