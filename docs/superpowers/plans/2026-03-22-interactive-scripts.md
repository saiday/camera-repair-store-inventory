# Interactive Scripts & Script-Based Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add interactive REPL mode to create/update scripts, move hook logic from server into scripts, and make brand searchable in the web UI.

**Architecture:** The mutation scripts (`create-item.sh`, `update-item.sh`) detect interactive mode via `$# -eq 0 && [ -t 0 ]` and prompt for input. After mutation, they call `update-owners.sh` and `generate-dashboard.sh` as background hooks (skippable with `--no-hooks`). The server passes `--no-hooks` to scripts and keeps its own synchronous `_run_hooks` so API responses wait for hooks to finish. Existing tests pass `--no-hooks` to avoid background hook side effects.

**Tech Stack:** Bash (3.2 compatible), Python 3, JavaScript

---

### Task 1: Add `--no-hooks` flag and hook calls to `create-item.sh`

**Files:**
- Modify: `scripts/create-item.sh`
- Test: `tests/test_create_item.sh`

- [ ] **Step 1: Write test for `--no-hooks` flag**

Add to `tests/test_create_item.sh`:

```bash
# --- Test: --no-hooks skips hook scripts ---
test_no_hooks_flag() {
  setup
  "$SCRIPT_DIR/create-item.sh" \
    --no-hooks \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null

  # Item should be created
  assert_dir_exists "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001" "item should exist"

  # owners.json should still be empty (hooks were skipped)
  local owners
  owners="$(cat "$TEST_TMP/data/owners.json")"
  assert_eq "[]" "$owners" "owners.json should remain empty when --no-hooks"

  teardown
}
```

Register it in the run section:

```bash
run_test "--no-hooks flag" test_no_hooks_flag
```

- [ ] **Step 2: Write test for hooks running by default**

Add to `tests/test_create_item.sh`:

```bash
# --- Test: hooks run by default (owners.json gets populated) ---
test_hooks_run_by_default() {
  setup

  "$SCRIPT_DIR/create-item.sh" \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null

  # Wait for background hooks to finish
  sleep 2

  # owners.json should now contain the owner
  local owners
  owners="$(cat "$TEST_TMP/data/owners.json")"
  assert_contains "$owners" "王小明" "owners.json should be updated by hooks"

  teardown
}
```

Register it:

```bash
run_test "hooks run by default" test_hooks_run_by_default
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bash tests/test_create_item.sh`
Expected: `--no-hooks` test fails (unknown argument), hooks test fails (owners.json still empty)

- [ ] **Step 4: Add `--no-hooks` to existing test calls**

Update all existing test functions in `tests/test_create_item.sh` (`test_create_basic`, `test_model_normalization`, `test_sequence_increment`, `test_initial_cost`, `test_category_prefixes`) to pass `--no-hooks` as the first flag after `create-item.sh`. This prevents background hooks from interfering with test teardown. Also update `tests/test_server.sh` test functions that call `create-item.sh` directly (`test_get_items`, `test_get_owners`, `test_get_item_raw`) to pass `--no-hooks`.

- [ ] **Step 5: Implement `--no-hooks` flag and hook calls in `create-item.sh`**

In `scripts/create-item.sh`, add `NO_HOOKS=""` to the variable declarations at line 17:

```bash
DATA_DIR="" CATEGORY="" BRAND="" MODEL="" SERIAL="" OWNER_NAME="" OWNER_CONTACT=""
DESCRIPTION="" DATE="" COST_AMOUNT="" COST_NOTE="" NO_HOOKS=""
```

Add the `--no-hooks` case to the while loop (before the `*` catch-all):

```bash
    --no-hooks) NO_HOOKS="1"; shift ;;
```

After the final `echo "$ITEM_ID"` line (line 117), add hook calls:

```bash
# --- Run hooks (unless --no-hooks) ---
if [[ -z "$NO_HOOKS" ]]; then
  "$SCRIPT_DIR/update-owners.sh" "$DATA_DIR" &
  "$SCRIPT_DIR/generate-dashboard.sh" "$DATA_DIR" &
fi
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test_create_item.sh`
Expected: All tests PASS

- [ ] **Step 7: Commit**

```bash
git add scripts/create-item.sh tests/test_create_item.sh tests/test_server.sh
git commit -m "feat: add --no-hooks flag and hook calls to create-item.sh"
```

---

### Task 2: Add `--no-hooks` flag and hook calls to `update-item.sh`

**Files:**
- Modify: `scripts/update-item.sh`
- Test: `tests/test_update_item.sh`

- [ ] **Step 1: Write test for `--no-hooks` flag**

Add to `tests/test_update_item.sh`:

```bash
# --- Test: --no-hooks skips hook scripts ---
test_no_hooks_flag() {
  setup
  local item_dir
  item_dir="$(create_test_item)"

  "$SCRIPT_DIR/update-item.sh" \
    --no-hooks \
    --item-dir "$item_dir" \
    --status "in_progress"

  # Update should succeed
  local output
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md")"
  assert_contains "$output" '"status": "in_progress"' "status should be updated"

  # owners.json should still be empty
  local owners
  owners="$(cat "$TEST_TMP/data/owners.json")"
  assert_eq "[]" "$owners" "owners.json should remain empty when --no-hooks"

  teardown
}
```

Register it:

```bash
run_test "--no-hooks flag" test_no_hooks_flag
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_update_item.sh`
Expected: FAIL — unknown argument `--no-hooks`

- [ ] **Step 3: Implement `--no-hooks` flag and hook calls in `update-item.sh`**

In `scripts/update-item.sh`, add `NO_HOOKS=""` to the variable declarations at line 16:

```bash
ITEM_DIR="" STATUS="" OWNER_NAME="" OWNER_CONTACT="" DESCRIPTION="" BRAND="" SERIAL=""
COST_AMOUNT="" COST_NOTE="" COST_DATE="" DELIVERED_DATE="" NO_HOOKS=""
```

Add the case to the while loop (before `*`):

```bash
    --no-hooks) NO_HOOKS="1"; shift ;;
```

After the validate line (`"$SCRIPT_DIR/parse-item.sh" "$ITEM_FILE" > /dev/null`, line 120), add:

```bash
# --- Run hooks (unless --no-hooks) ---
if [[ -z "$NO_HOOKS" ]]; then
  # Derive data-dir from item-dir (two levels up: repairs/<id>/item.md → data/)
  HOOKS_DATA_DIR="$(cd "$ITEM_DIR/../.." && pwd)"
  "$SCRIPT_DIR/update-owners.sh" "$HOOKS_DATA_DIR" &
  "$SCRIPT_DIR/generate-dashboard.sh" "$HOOKS_DATA_DIR" &
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_update_item.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/update-item.sh tests/test_update_item.sh
git commit -m "feat: add --no-hooks flag and hook calls to update-item.sh"
```

---

### Task 3: Add `--no-hooks` to server's script calls

The server keeps its synchronous `_run_hooks` (so API responses wait for hooks to finish) but passes `--no-hooks` to the scripts to prevent double-hook execution. CLI usage gets automatic background hooks; server usage gets synchronous hooks.

**Files:**
- Modify: `scripts/server.py`
- Test: `tests/test_server.sh`

- [ ] **Step 1: Run existing server tests to confirm they pass before changes**

Run: `bash tests/test_server.sh`
Expected: All tests PASS

- [ ] **Step 2: Add `--no-hooks` to server's script calls**

In `_handle_create`, add `'--no-hooks'` to the cmd list right after the `create-item.sh` path:

```python
        cmd = [
            os.path.join(self.scripts_dir, 'create-item.sh'),
            '--no-hooks',
            '--data-dir', self.data_dir,
```

In `_handle_update`, add `'--no-hooks'` to the cmd list:

```python
        cmd = [os.path.join(self.scripts_dir, 'update-item.sh'), '--no-hooks', '--item-dir', item_dir]
```

- [ ] **Step 3: Run server tests to verify they still pass**

Run: `bash tests/test_server.sh`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add scripts/server.py
git commit -m "refactor: server passes --no-hooks to prevent double hook execution"
```

---

### Task 4: Add interactive mode to `create-item.sh`

**Files:**
- Modify: `scripts/create-item.sh`

- [ ] **Step 1: Add interactive mode block**

Insert after the `SCRIPT_DIR` line (line 13) and before the variable declarations (line 16), add the interactive mode block:

```bash
# --- Helper: prompt until non-empty ---
prompt_required() {
  local prompt_text="$1" value=""
  while true; do
    printf '%s' "$prompt_text" >&2
    read -r value
    if [[ -n "$value" ]]; then
      echo "$value"
      return
    fi
    echo "This field is required." >&2
  done
}

# --- Interactive mode: prompt for each field when no args and TTY ---
if [[ $# -eq 0 && -t 0 ]]; then
  DATA_DIR="${SCRIPT_DIR}/../data"

  # Category (validated against enum)
  while true; do
    printf 'Category (camera/lens/accessory/misc): ' >&2
    read -r CATEGORY
    case "$CATEGORY" in
      camera|lens|accessory|misc) break ;;
      *) echo "Invalid category. Choose: camera, lens, accessory, misc" >&2 ;;
    esac
  done

  BRAND="$(prompt_required 'Brand: ')"
  MODEL="$(prompt_required 'Model: ')"
  SERIAL="$(prompt_required 'Serial: ')"
  OWNER_NAME="$(prompt_required 'Owner: ')"
  OWNER_CONTACT="$(prompt_required 'Contact: ')"
  DESCRIPTION="$(prompt_required 'Description: ')"

  TODAY="$(date +%Y-%m-%d)"
  printf 'Date [%s]: ' "$TODAY" >&2
  read -r DATE
  DATE="${DATE:-$TODAY}"

  # Fall through to the rest of the script with variables set
  NO_HOOKS=""
  COST_AMOUNT=""
  COST_NOTE=""
else
```

Then wrap the existing argument parsing block (lines 16-47) as the `else` branch, and close with `fi`:

After the existing validation `done` (line 47), add:

```bash
fi
```

- [ ] **Step 2: Test interactively**

Run manually: `scripts/create-item.sh`
Enter values when prompted. Verify the item is created and output shows the ID with a checkmark.

- [ ] **Step 3: Add success message for interactive mode**

Change the final output line. Replace `echo "$ITEM_ID"` with:

```bash
if [[ -t 1 ]]; then
  echo "✓ Created $ITEM_ID" >&2
fi
echo "$ITEM_ID"
```

This prints the friendly message to stderr (visible in terminal) while keeping stdout clean for scripts.

- [ ] **Step 4: Run existing tests to verify non-interactive mode still works**

Run: `bash tests/test_create_item.sh`
Expected: All tests PASS (tests pass args, so they don't enter interactive mode)

- [ ] **Step 5: Commit**

```bash
git add scripts/create-item.sh
git commit -m "feat: add interactive REPL mode to create-item.sh"
```

---

### Task 5: Add interactive mode to `update-item.sh`

**Files:**
- Modify: `scripts/update-item.sh`

- [ ] **Step 1: Add interactive mode block with search**

Insert after the `SCRIPT_DIR` line (line 13) and before the variable declarations (line 16), add:

```bash
# --- Interactive mode: search and prompt when no args and TTY ---
if [[ $# -eq 0 && -t 0 ]]; then
  DATA_DIR="${SCRIPT_DIR}/../data"
  REPAIRS_DIR="$DATA_DIR/repairs"

  printf 'Search: ' >&2
  read -r SEARCH_QUERY

  # Direct item ID match — skip search if input is an exact directory name
  if [[ -d "$REPAIRS_DIR/$SEARCH_QUERY" && -f "$REPAIRS_DIR/$SEARCH_QUERY/item.md" ]]; then
    ITEM_DIR="$REPAIRS_DIR/$SEARCH_QUERY"
  else

  # Search items by brand, model, owner, or ID (case-insensitive)
  MATCHES=()
  MATCH_DIRS=()
  if [[ -d "$REPAIRS_DIR" ]]; then
    for dir in "$REPAIRS_DIR"/*/; do
      [[ -f "$dir/item.md" ]] || continue
      local_json="$("$SCRIPT_DIR/parse-item.sh" "$dir/item.md" 2>/dev/null)" || continue
      local_id="$(echo "$local_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'])")"
      local_brand="$(echo "$local_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['brand'])")"
      local_model="$(echo "$local_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['model'])")"
      local_owner="$(echo "$local_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['owner_name'])")"

      # Case-insensitive match
      QUERY_LOWER="$(echo "$SEARCH_QUERY" | tr '[:upper:]' '[:lower:]')"
      HAYSTACK="$(echo "$local_id $local_brand $local_model $local_owner" | tr '[:upper:]' '[:lower:]')"
      if [[ "$HAYSTACK" == *"$QUERY_LOWER"* ]]; then
        MATCHES+=("$local_id — $local_brand $local_model ($local_owner)")
        MATCH_DIRS+=("${dir%/}")
      fi
    done
  fi

  if [[ ${#MATCHES[@]} -eq 0 ]]; then
    echo "No items found matching '$SEARCH_QUERY'" >&2
    exit 1
  elif [[ ${#MATCHES[@]} -eq 1 ]]; then
    ITEM_DIR="${MATCH_DIRS[0]}"
    echo "  ${MATCHES[0]}" >&2
  else
    for i in "${!MATCHES[@]}"; do
      echo "  $((i+1))) ${MATCHES[$i]}" >&2
    done
    printf 'Select [1]: ' >&2
    read -r SELECTION
    SELECTION="${SELECTION:-1}"
    IDX=$((SELECTION - 1))
    if [[ $IDX -lt 0 || $IDX -ge ${#MATCHES[@]} ]]; then
      echo "Invalid selection" >&2
      exit 1
    fi
    ITEM_DIR="${MATCH_DIRS[$IDX]}"
  fi

  fi  # end of search branch (direct ID match skips here)

  # Parse current item for display
  CURRENT_JSON="$("$SCRIPT_DIR/parse-item.sh" "$ITEM_DIR/item.md")"
  CURRENT_STATUS="$(echo "$CURRENT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])")"
  CURRENT_BRAND="$(echo "$CURRENT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['brand'])")"
  CURRENT_MODEL="$(echo "$CURRENT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['model'])")"
  CURRENT_OWNER="$(echo "$CURRENT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['owner_name'])")"

  echo "" >&2
  echo "Current: status=$CURRENT_STATUS, brand=$CURRENT_BRAND, model=$CURRENT_MODEL, owner=$CURRENT_OWNER" >&2
  printf 'New status (not_started/in_progress/testing/done/delivered/ice_box) [%s]: ' "$CURRENT_STATUS" >&2
  read -r STATUS
  STATUS="${STATUS:-}"

  printf 'Add cost? (y/N): ' >&2
  read -r ADD_COST
  COST_AMOUNT="" COST_NOTE="" COST_DATE=""
  if [[ "$ADD_COST" =~ ^[Yy]$ ]]; then
    printf '  Amount: ' >&2
    read -r COST_AMOUNT
    printf '  Note: ' >&2
    read -r COST_NOTE
  fi

  # Set remaining vars to empty (not updating)
  OWNER_NAME="" OWNER_CONTACT="" DESCRIPTION="" BRAND="" SERIAL=""
  DELIVERED_DATE="" NO_HOOKS=""

  # If status is delivered, auto-set delivered_date
  if [[ "$STATUS" == "delivered" ]]; then
    DELIVERED_DATE="$(date +%Y-%m-%d)"
  fi

  ITEM_FILE="$ITEM_DIR/item.md"
  # Skip to the Python update section
else
```

Wrap the existing argument parsing (lines 16-44) as the else branch, and close with `fi` after line 44.

- [ ] **Step 2: Add success message for interactive mode**

After the validate line, before the hooks section, add:

```bash
# --- Success message for interactive mode ---
if [[ -t 0 && -t 1 ]]; then
  ITEM_ID="$(basename "$ITEM_DIR")"
  echo "✓ Updated $ITEM_ID" >&2
fi
```

- [ ] **Step 3: Test interactively**

Run manually: `scripts/update-item.sh`
Search for "nikon", select an item, change status. Verify the update works.

- [ ] **Step 4: Run existing tests to verify non-interactive mode still works**

Run: `bash tests/test_update_item.sh`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/update-item.sh
git commit -m "feat: add interactive REPL mode with search to update-item.sh"
```

---

### Task 6: Add brand to web UI search

**Files:**
- Modify: `web/static/entry.js`

- [ ] **Step 1: Find current search filter in entry.js**

In `web/static/entry.js`, locate the search filter around line 165. The current filter matches `id`, `model`, and `owner_name`.

- [ ] **Step 2: Add `brand` to search filter**

Change:

```javascript
const matches = allItems.filter(function(item) {
  return item.id.toLowerCase().includes(q) ||
         item.model.toLowerCase().includes(q) ||
         item.owner_name.toLowerCase().includes(q);
});
```

To:

```javascript
const matches = allItems.filter(function(item) {
  return item.id.toLowerCase().includes(q) ||
         item.brand.toLowerCase().includes(q) ||
         item.model.toLowerCase().includes(q) ||
         item.owner_name.toLowerCase().includes(q);
});
```

- [ ] **Step 3: Test in browser**

Start server: `scripts/server.sh`
Open http://localhost:8787/entry.html
Search for "Rolleiflex" — should match Rolleiflex items by brand.
Search for "Minolta" — should match all Minolta items.

- [ ] **Step 4: Commit**

```bash
git add web/static/entry.js
git commit -m "feat: add brand to search filter in entry page"
```

---

### Task 7: Run all tests and verify

- [ ] **Step 1: Run all test suites**

```bash
bash tests/test_create_item.sh
bash tests/test_update_item.sh
bash tests/test_server.sh
```

Expected: All tests PASS across all suites.

- [ ] **Step 2: Manual smoke test**

```bash
# Interactive create
scripts/create-item.sh

# Interactive update
scripts/update-item.sh

# Batch with --no-hooks
scripts/create-item.sh --no-hooks --data-dir ./data --category misc --brand Test --model "Batch" --serial "999" --owner-name "Test" --owner-contact "test" --description "batch test" --date 2026-03-22

# Verify hooks don't run for --no-hooks
cat data/owners.json  # should NOT contain "Test" owner

# Run hooks manually
scripts/update-owners.sh
scripts/generate-dashboard.sh
```

- [ ] **Step 3: Clean up test items**

Remove any test items created during smoke testing.
