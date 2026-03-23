# Kanban Select & Move Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a selection mode to the kanban dashboard so users can select cards and batch-move them to a different status without leaving the board.

**Architecture:** Pure client-side feature. `generate-dashboard.sh` emits new HTML elements (select button, move-bar, data attributes). `dashboard.js` handles all interaction logic. Existing `/api/update` endpoint is used as-is for status changes.

**Tech Stack:** Bash 3.2, Python 3 stdlib (inside generate-dashboard.sh), vanilla HTML/CSS/JS

**Spec:** `docs/superpowers/specs/2026-03-23-kanban-select-and-move-design.md`

---

### Task 1: Add `data-item-id` to card elements

**Files:**
- Modify: `scripts/generate-dashboard.sh:53-54` (render_card function)
- Modify: `tests/test_generate_dashboard.sh`

- [ ] **Step 1: Write failing test**

Add to `tests/test_generate_dashboard.sh`, before the "Run all tests" section:

```bash
# --- Test: cards have data-item-id attribute ---
test_card_has_item_id() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "not_started" "王小明" "EOS R5"

  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  local content
  content="$(cat "$TEST_TMP/web/dashboard.html")"
  assert_contains "$content" 'data-item-id="CAM-20260322-EOS-R5-001"' "card should have data-item-id attribute"
  teardown
}
```

Register it in the "Run all tests" section:

```bash
run_test "cards have data-item-id" test_card_has_item_id
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_generate_dashboard.sh`
Expected: FAIL on "cards have data-item-id"

- [ ] **Step 3: Add data-item-id to render_card**

In `scripts/generate-dashboard.sh`, modify the `render_card` function. Change line 54 from:

```python
        f'<a class="card" href="entry.html?id={eid}" data-received="{edate}">'
```

to:

```python
        f'<a class="card" href="entry.html?id={eid}" data-received="{edate}" data-item-id="{eid}">'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_generate_dashboard.sh`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-dashboard.sh tests/test_generate_dashboard.sh
git commit -m "feat: add data-item-id attribute to kanban cards"
```

---

### Task 2: Add select toggle button and move-bar HTML

**Files:**
- Modify: `scripts/generate-dashboard.sh:89-114` (HTML template)
- Modify: `tests/test_generate_dashboard.sh`

- [ ] **Step 1: Write failing tests**

Add to `tests/test_generate_dashboard.sh`, before the "Run all tests" section:

```bash
# --- Test: dashboard has select toggle button ---
test_has_select_toggle() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "not_started" "王小明" "EOS R5"

  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  local content
  content="$(cat "$TEST_TMP/web/dashboard.html")"
  assert_contains "$content" "select-toggle" "should have select toggle button"
  assert_contains "$content" "選取" "select button should have Chinese label"
  teardown
}

# --- Test: dashboard has move-bar ---
test_has_move_bar() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "not_started" "王小明" "EOS R5"

  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  local content
  content="$(cat "$TEST_TMP/web/dashboard.html")"
  assert_contains "$content" "move-bar" "should have move-bar element"
  assert_contains "$content" "not_started" "move-bar should contain status API values"
  assert_contains "$content" "進行中" "move-bar should contain Chinese labels"
  teardown
}
```

Register them:

```bash
run_test "has select toggle" test_has_select_toggle
run_test "has move-bar" test_has_move_bar
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_generate_dashboard.sh`
Expected: FAIL on "has select toggle" and "has move-bar"

- [ ] **Step 3: Add select button and move-bar to HTML template**

In `scripts/generate-dashboard.sh`, modify the HTML template. Change the toolbar `<nav>` section (around line 98-101) from:

```python
  <nav class=\"toolbar\">
    <a href=\"entry.html\">維修單</a>
    <a href=\"dashboard.html\" class=\"active\">看板</a>
  </nav>
```

to:

```python
  <nav class=\"toolbar\">
    <a href=\"entry.html\">維修單</a>
    <a href=\"dashboard.html\" class=\"active\">看板</a>
    <button class=\"select-toggle\" onclick=\"toggleSelectMode()\">選取</button>
  </nav>
```

Then add the move-bar just before `<script src=\"static/dashboard.js\">` (around line 112):

```python
  <div class=\"move-bar\" style=\"display:none\">
    <div class=\"move-bar-count\">已選 0 件 — 移動到：</div>
    <div class=\"move-bar-pills\">
      <button class=\"status-pill\" data-status=\"not_started\">未開始</button>
      <button class=\"status-pill\" data-status=\"in_progress\">進行中</button>
      <button class=\"status-pill\" data-status=\"testing\">測試中</button>
      <button class=\"status-pill\" data-status=\"done\">完成\u30fb待取件</button>
      <button class=\"status-pill\" data-status=\"ice_box\">冰箱</button>
    </div>
    <button class=\"move-bar-cancel\" onclick=\"toggleSelectMode()\">取消</button>
  </div>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_generate_dashboard.sh`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-dashboard.sh tests/test_generate_dashboard.sh
git commit -m "feat: add select toggle button and move-bar to dashboard HTML"
```

---

### Task 3: Add CSS for selection mode

**Files:**
- Modify: `web/static/style.css` (append after ice-box section, before entry page section)

- [ ] **Step 1: Add selection mode styles**

Insert the following CSS in `web/static/style.css` after line 114 (`.section-cards .card { width: 240px; }`) and before line 116 (`/* --- Entry Page --- */`):

```css
/* --- Selection Mode --- */
.select-toggle {
  margin-left: auto;
  padding: 8px 16px;
  background: #f0f0f0;
  border: 1px solid #ddd;
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
  color: #555;
}
.select-toggle:hover { background: #e8e8e8; }
.select-toggle.active {
  background: #333;
  color: #fff;
  border-color: #333;
}
.card.selected {
  background: #e8f4fd;
  border: 2px solid #4a90d9;
  padding: 11px; /* compensate for 2px border vs 1px */
}
.card.selected::after {
  content: "✓";
  position: absolute;
  top: 6px;
  right: 6px;
  width: 20px;
  height: 20px;
  background: #4a90d9;
  color: #fff;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
}
.selecting .card {
  position: relative;
}
.move-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: #fff;
  border-top: 1px solid #ddd;
  padding: 12px 24px;
  box-shadow: 0 -2px 8px rgba(0,0,0,0.06);
  z-index: 100;
}
.move-bar-count {
  font-size: 13px;
  color: #666;
  margin-bottom: 8px;
}
.move-bar-pills {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.status-pill {
  padding: 8px 16px;
  border-radius: 20px;
  border: none;
  font-size: 13px;
  cursor: pointer;
  font-weight: 500;
}
.status-pill[data-status="not_started"] { background: #f5f5f5; color: #666; }
.status-pill[data-status="in_progress"] { background: #e8f4fd; color: #2c7be5; }
.status-pill[data-status="testing"] { background: #fff3e0; color: #e65100; }
.status-pill[data-status="done"] { background: #e8f5e9; color: #2e7d32; }
.status-pill[data-status="ice_box"] { background: #f3e5f5; color: #7b1fa2; }
.status-pill.disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.move-bar-cancel {
  margin-top: 8px;
  padding: 6px 16px;
  background: #f5f5f5;
  border: 1px solid #ddd;
  border-radius: 6px;
  font-size: 13px;
  cursor: pointer;
  color: #999;
}
```

- [ ] **Step 2: Verify dashboard still renders**

Run: `bash tests/test_generate_dashboard.sh`
Expected: all PASS (CSS changes don't affect HTML generation, but confirms nothing is broken)

- [ ] **Step 3: Commit**

```bash
git add web/static/style.css
git commit -m "feat: add CSS for kanban selection mode and move-bar"
```

---

### Task 4: Implement selection mode toggle and card selection JS

**Files:**
- Modify: `web/static/dashboard.js`

- [ ] **Step 1: Add selection mode state and toggle function**

Append the following to `web/static/dashboard.js` after the existing DOMContentLoaded block:

```javascript
// --- Selection Mode ---
let selectMode = false;
let selectedIds = [];

function toggleSelectMode() {
  selectMode = !selectMode;
  const toggle = document.querySelector('.select-toggle');
  const moveBar = document.querySelector('.move-bar');

  if (selectMode) {
    document.body.classList.add('selecting');
    toggle.classList.add('active');
    toggle.textContent = '取消選取';
    moveBar.style.display = '';
    updateMoveBar();
  } else {
    document.body.classList.remove('selecting');
    toggle.classList.remove('active');
    toggle.textContent = '選取';
    moveBar.style.display = 'none';
    clearSelection();
  }
}

function clearSelection() {
  selectedIds = [];
  document.querySelectorAll('.card.selected').forEach(function(card) {
    card.classList.remove('selected');
  });
}

function updateMoveBar() {
  const countEl = document.querySelector('.move-bar-count');
  if (countEl) {
    countEl.textContent = '已選 ' + selectedIds.length + ' 件 — 移動到：';
  }
  document.querySelectorAll('.status-pill').forEach(function(pill) {
    if (selectedIds.length === 0) {
      pill.classList.add('disabled');
    } else {
      pill.classList.remove('disabled');
    }
  });
}
```

- [ ] **Step 2: Add card click handler for selection**

Append to `web/static/dashboard.js`:

```javascript
document.addEventListener('click', function(e) {
  if (!selectMode) return;

  const card = e.target.closest('.card');
  if (!card) return;

  e.preventDefault();

  const itemId = card.getAttribute('data-item-id');
  if (!itemId) return;

  const idx = selectedIds.indexOf(itemId);
  if (idx === -1) {
    selectedIds.push(itemId);
    card.classList.add('selected');
  } else {
    selectedIds.splice(idx, 1);
    card.classList.remove('selected');
  }
  updateMoveBar();
});
```

- [ ] **Step 3: Manual test**

Start the dev server (`python3 scripts/server.py`), open the dashboard, and verify:
1. "選取" button visible in toolbar
2. Clicking it enters selection mode (button changes to "取消選取")
3. Tapping a card selects it (blue highlight, checkmark)
4. Tapping again deselects it
5. Count in move-bar updates
6. Clicking "取消選取" or "取消" exits selection mode and clears selection
7. In normal mode, tapping a card still navigates to entry page

- [ ] **Step 4: Commit**

```bash
git add web/static/dashboard.js
git commit -m "feat: implement selection mode toggle and card selection"
```

---

### Task 5: Implement move-bar status pill action with API calls

**Files:**
- Modify: `web/static/dashboard.js`

- [ ] **Step 1: Add status pill click handler and batch update**

Append to `web/static/dashboard.js`:

```javascript
document.addEventListener('click', function(e) {
  const pill = e.target.closest('.status-pill');
  if (!pill || !selectMode) return;
  if (pill.classList.contains('disabled')) return;

  const status = pill.getAttribute('data-status');
  const label = pill.textContent;
  const count = selectedIds.length;

  if (!confirm('確定移動 ' + count + ' 件到 ' + label + '？')) return;

  const ids = selectedIds.slice();
  let succeeded = 0;
  let i = 0;

  function next() {
    if (i >= ids.length) {
      location.reload();
      return;
    }
    const id = ids[i];
    i++;
    fetch('/api/update', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: id, status: status })
    }).then(function(res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      succeeded++;
      next();
    }).catch(function() {
      const failed = ids.length - succeeded;
      alert('完成 ' + succeeded + ' 件，失敗 ' + failed + ' 件');
      location.reload();
    });
  }

  next();
});
```

- [ ] **Step 2: Manual test**

With the dev server running and at least two items in the system:
1. Enter selection mode, select 1-2 cards
2. Tap a status pill → confirmation dialog appears with correct count and label
3. Confirm → items move to new status, page reloads, cards appear in new column
4. Cancel the confirmation → nothing changes
5. Test with 0 items selected → pill should be disabled (not clickable)

- [ ] **Step 3: Commit**

```bash
git add web/static/dashboard.js
git commit -m "feat: implement batch status move via move-bar pills"
```

---

### Task 6: Handle ice box collapse during selection mode

**Files:**
- Modify: `scripts/generate-dashboard.sh:105` (ice box toggle onclick)
- Modify: `web/static/dashboard.js`

- [ ] **Step 1: Update ice box toggle to call JS function**

In `scripts/generate-dashboard.sh`, change the ice box toggle onclick (around line 105) from:

```python
    <h2 class=\"section-toggle\" onclick=\"this.parentElement.classList.toggle(\'collapsed\')\">
```

to:

```python
    <h2 class=\"section-toggle\" onclick=\"toggleIceBox(this)\">
```

- [ ] **Step 2: Add toggleIceBox function to dashboard.js**

Append to `web/static/dashboard.js`:

```javascript
function toggleIceBox(el) {
  const iceBox = el.parentElement;
  iceBox.classList.toggle('collapsed');

  if (selectMode && iceBox.classList.contains('collapsed')) {
    iceBox.querySelectorAll('.card.selected').forEach(function(card) {
      const itemId = card.getAttribute('data-item-id');
      const idx = selectedIds.indexOf(itemId);
      if (idx !== -1) {
        selectedIds.splice(idx, 1);
      }
      card.classList.remove('selected');
    });
    updateMoveBar();
  }
}
```

- [ ] **Step 3: Manual test**

1. Enter selection mode
2. Expand ice box, select an ice box card
3. Collapse ice box → selected count should decrease
4. Expand ice box again → card should not be selected anymore
5. Outside selection mode, ice box toggle still works normally

- [ ] **Step 4: Run existing tests to verify no regressions**

Run: `bash tests/test_generate_dashboard.sh && bash tests/test_server.sh`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-dashboard.sh web/static/dashboard.js
git commit -m "feat: deselect ice box cards when section is collapsed"
```

---

### Task 7: Integration test — batch status move via server

**Files:**
- Modify: `tests/test_server.sh`

- [ ] **Step 1: Write integration test**

Add to `tests/test_server.sh`, before the "Run all tests" section:

```bash
# --- Test: POST /api/update changes item status ---
test_update_status() {
  setup
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  start_server
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/update" \
    -H "Content-Type: application/json" \
    -d '{"id": "CAM-20260322-EOS-R5-001", "status": "in_progress"}')"
  assert_contains "$response" '"ok"' "update should return ok"

  # Verify the item status changed
  local raw
  raw="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$raw" "status: in_progress" "item status should be updated"
  stop_server
  teardown
}
```

Register it:

```bash
run_test "POST /api/update status" test_update_status
```

- [ ] **Step 2: Run test**

Run: `bash tests/test_server.sh`
Expected: all PASS (this tests the existing endpoint the move-bar relies on)

- [ ] **Step 3: Commit**

```bash
git add tests/test_server.sh
git commit -m "test: add integration test for status update API"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

```bash
bash tests/test_generate_dashboard.sh && bash tests/test_server.sh
```

Expected: all PASS

- [ ] **Step 2: End-to-end manual test on mobile (or mobile emulation)**

Open the dashboard in a mobile browser or Chrome DevTools mobile emulation:
1. "選取" button is visible and easy to tap
2. Enter selection mode → select multiple cards across columns
3. Tap a status pill → confirmation → cards move
4. Move-bar has good touch targets (pills are large enough)
5. Ice box expand/collapse works correctly during selection
6. Exiting selection mode clears everything
7. Normal mode card taps still navigate to entry page
