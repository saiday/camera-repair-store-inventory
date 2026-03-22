# Camera Repair Shop Inventory System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a file-based inventory system for a camera repair shop with structured Markdown as the data store, shell scripts for data operations, and a local web UI in Traditional Chinese.

**Architecture:** Structured Markdown files (`item.md`) are the single source of truth for each repair item. Shell scripts (Bash) handle all CRUD and validation. A Python stdlib HTTP server provides the web layer — serving static HTML and proxying form submissions to shell scripts. Two web pages: a static entry/edit form and a generated kanban dashboard.

**Tech Stack:** Bash (data scripts — POSIX-compatible, no bash 4+ features since macOS ships bash 3.2), Python 3 stdlib (HTTP server + parse-item helper), vanilla HTML/CSS/JS (frontend)

**Bash compatibility note:** macOS ships with bash 3.2. Do NOT use bash 4+ features: no `declare -A` (associative arrays), no `local -n` (namerefs), no `${!var}` (indirect expansion in some contexts). Use Python helpers where associative data structures are needed.

**Hook calling design:** Shell scripts (create-item.sh, update-item.sh) do NOT call update-owners.sh or generate-dashboard.sh directly. Hooks are called by server.py after successful API operations via `_run_hooks()`. This means CLI-only usage won't auto-update owners.json or the dashboard — acceptable for this single-user system where the web UI is the primary interface.

**Methodology:** Follow strict TDD for Tasks 2-5 and 7. For each task: write the test first, run it to confirm it fails, then write the minimal implementation to make it pass. Do not write implementation code before the test exists and has been run. Tasks 1, 6, 8, and 9 are scaffolding/frontend/docs — no TDD, verify by manual testing.

**Spec:** `docs/superpowers/specs/2026-03-22-camera-repair-inventory-design.md`

---

## File Structure

```
camera-repair-store-inventory/
  data/
    repairs/                          # repair item directories (created at runtime)
    owners.json                       # auto-maintained owner registry
  scripts/
    server.sh                         # one-command start: checks python3, kills port 8787 if busy, runs server.py
    server.py                         # Python HTTP server (stdlib http.server, custom handler)
    create-item.sh                    # creates new repair item directory + item.md + logs/
    update-item.sh                    # updates an existing item's item.md
    parse-item.sh                     # shared parser/validator for item.md → outputs JSON
    update-owners.sh                  # hook: rebuilds owners.json from all item.md files
    generate-dashboard.sh             # reads all items via parse-item.sh, writes web/dashboard.html
  web/
    entry.html                        # static: create/edit form (JS loads data from APIs)
    dashboard.html                    # generated: kanban board (regenerated after mutations)
    static/
      style.css                       # shared styles for both pages
      entry.js                        # entry page logic: form, search, autocomplete, markdown parsing
      dashboard.js                    # dashboard logic: compute days-since-received
  tests/
    test_parse_item.sh                # tests for parse-item.sh
    test_create_item.sh               # tests for create-item.sh
    test_update_item.sh               # tests for update-item.sh
    test_update_owners.sh             # tests for update-owners.sh
    test_generate_dashboard.sh        # tests for generate-dashboard.sh
    test_server.sh                    # integration tests for server.py API endpoints
    helpers.sh                        # shared test utilities (setup, teardown, assertions)
  docs/
    format.md                         # documents the item.md schema for humans & agents
```

---

## Task 1: Test Harness and Project Scaffolding

**Files:**
- Create: `tests/helpers.sh`
- Create: `data/repairs/.gitkeep`
- Create: `data/owners.json`
- Create: `.gitignore`

- [ ] **Step 1: Create .gitignore**

```gitignore
.superpowers/
web/dashboard.html
```

- [ ] **Step 2: Create test helpers**

```bash
#!/usr/bin/env bash
# tests/helpers.sh — shared test utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
TEST_TMP=""

setup() {
  TEST_TMP="$(mktemp -d)"
  mkdir -p "$TEST_TMP/data/repairs"
  echo '[]' > "$TEST_TMP/data/owners.json"
}

teardown() {
  [[ -n "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${msg:-assert_eq}"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: ${msg:-assert_contains}"
    echo "  expected to contain: $needle"
    echo "  actual: $haystack"
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: ${msg:-assert_file_exists} — file not found: $path"
    return 1
  fi
}

assert_dir_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -d "$path" ]]; then
    echo "FAIL: ${msg:-assert_dir_exists} — directory not found: $path"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${msg:-assert_exit_code}"
    echo "  expected exit code: $expected"
    echo "  actual exit code:   $actual"
    return 1
  fi
}

pass() {
  echo "PASS: $1"
}
```

- [ ] **Step 3: Create data scaffolding**

Create `data/repairs/.gitkeep` (empty file) and `data/owners.json`:

```json
[]
```

- [ ] **Step 4: Commit**

```bash
git add .gitignore tests/helpers.sh data/repairs/.gitkeep data/owners.json
git commit -m "feat: add test harness, project scaffolding, and .gitignore"
```

---

## Task 2: parse-item.sh — Markdown Parser and Validator

**Files:**
- Create: `scripts/parse-item.sh`
- Create: `tests/test_parse_item.sh`

This is the foundational script. Every other script depends on it. It reads an `item.md` file, validates the structure, and outputs a JSON representation of the frontmatter fields.

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/test_parse_item.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
    ((PASS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
}

# --- Test: valid item.md parses to JSON ---
test_valid_parse() {
  setup
  local item_dir="$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001"
  mkdir -p "$item_dir"
  cat > "$item_dir/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345678"
status: not_started
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
ITEM

  local output
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md")"
  local exit_code=$?
  assert_eq "0" "$exit_code" "parse should succeed"
  assert_contains "$output" '"id": "CAM-20260322-EOS-R5-001"' "should contain id"
  assert_contains "$output" '"category": "camera"' "should contain category"
  assert_contains "$output" '"owner_name": "王小明"' "should contain owner_name"
  assert_contains "$output" '"status": "not_started"' "should contain status"
  teardown
}

# --- Test: missing required field ---
test_missing_field() {
  setup
  local item_dir="$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001"
  mkdir -p "$item_dir"
  cat > "$item_dir/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
status: not_started
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

Test

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
ITEM

  local output exit_code
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md" 2>&1)" || exit_code=$?
  assert_eq "1" "$exit_code" "should fail with exit code 1"
  assert_contains "$output" "serial_number" "error should mention missing field"
  teardown
}

# --- Test: invalid status value ---
test_invalid_status() {
  setup
  local item_dir="$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001"
  mkdir -p "$item_dir"
  cat > "$item_dir/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345678"
status: broken
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

Test

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
ITEM

  local output exit_code
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md" 2>&1)" || exit_code=$?
  assert_eq "1" "$exit_code" "should fail for invalid status"
  assert_contains "$output" "status" "error should mention status"
  teardown
}

# --- Test: missing body section ---
test_missing_body_section() {
  setup
  local item_dir="$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001"
  mkdir -p "$item_dir"
  cat > "$item_dir/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345678"
status: not_started
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

Test description here
ITEM

  local output exit_code
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md" 2>&1)" || exit_code=$?
  assert_eq "1" "$exit_code" "should fail for missing cost section"
  assert_contains "$output" "費用紀錄" "error should mention missing section"
  teardown
}

# --- Test: file not found ---
test_file_not_found() {
  setup
  local output exit_code
  output="$("$SCRIPT_DIR/parse-item.sh" "$TEST_TMP/nonexistent.md" 2>&1)" || exit_code=$?
  assert_eq "1" "$exit_code" "should fail for missing file"
  assert_contains "$output" "not found" "error should mention file not found"
  teardown
}

# --- Run all tests ---
echo "=== parse-item.sh tests ==="
run_test "valid parse" test_valid_parse
run_test "missing required field" test_missing_field
run_test "invalid status" test_invalid_status
run_test "missing body section" test_missing_body_section
run_test "file not found" test_file_not_found

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_parse_item.sh`
Expected: FAIL (parse-item.sh does not exist yet)

- [ ] **Step 3: Implement parse-item.sh**

This script uses Python (via inline script) to parse the YAML frontmatter and validate it, since bash 3.2 lacks associative arrays. The shell script is a thin wrapper.

```bash
#!/usr/bin/env bash
# scripts/parse-item.sh — Parse and validate an item.md file, output JSON
#
# Usage: parse-item.sh <path-to-item.md>
# Output: JSON object with frontmatter fields on stdout
# Errors: prints to stderr, exits with code 1

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR: Usage: parse-item.sh <path-to-item.md>" >&2
  exit 1
fi

ITEM_FILE="$1"

if [[ ! -f "$ITEM_FILE" ]]; then
  echo "ERROR: item.md not found: $ITEM_FILE" >&2
  exit 1
fi

python3 -c "
import sys, json, os, re

item_file = sys.argv[1]
item_id = os.path.basename(os.path.dirname(item_file))

with open(item_file, 'r') as f:
    content = f.read()

# Parse frontmatter
fm_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not fm_match:
    print(f'ERROR: item.md parse failed — no frontmatter found in {item_id}', file=sys.stderr)
    sys.exit(1)

fields = {}
for line in fm_match.group(1).split('\n'):
    colon_idx = line.find(':')
    if colon_idx > 0:
        key = line[:colon_idx].strip()
        value = line[colon_idx+1:].strip()
        # Remove surrounding quotes
        if value.startswith('\"') and value.endswith('\"'):
            value = value[1:-1]
        fields[key] = value

# Validate required fields
required = ['id','category','brand','model','serial_number','status','owner_name','owner_contact','received_date']
for field in required:
    if not fields.get(field):
        print(f\"ERROR: item.md parse failed — missing required field '{field}' in {item_id}\", file=sys.stderr)
        sys.exit(1)

# Validate enums
valid_statuses = ['not_started','in_progress','testing','done','delivered','ice_box']
if fields['status'] not in valid_statuses:
    print(f\"ERROR: item.md parse failed — invalid status '{fields['status']}' in {item_id} (valid: {' '.join(valid_statuses)})\", file=sys.stderr)
    sys.exit(1)

valid_categories = ['camera','lens','accessory','misc']
if fields['category'] not in valid_categories:
    print(f\"ERROR: item.md parse failed — invalid category '{fields['category']}' in {item_id} (valid: {' '.join(valid_categories)})\", file=sys.stderr)
    sys.exit(1)

# Validate body sections (content after the closing ---)
body = content[fm_match.end():]
if '# 維修描述' not in body:
    print(f'ERROR: item.md parse failed — missing section \"# 維修描述\" in {item_id}', file=sys.stderr)
    sys.exit(1)
if '# 費用紀錄' not in body:
    print(f'ERROR: item.md parse failed — missing section \"# 費用紀錄\" in {item_id}', file=sys.stderr)
    sys.exit(1)

# Output JSON
result = {
    'id': fields.get('id', ''),
    'category': fields.get('category', ''),
    'brand': fields.get('brand', ''),
    'model': fields.get('model', ''),
    'serial_number': fields.get('serial_number', ''),
    'status': fields.get('status', ''),
    'owner_name': fields.get('owner_name', ''),
    'owner_contact': fields.get('owner_contact', ''),
    'received_date': fields.get('received_date', ''),
    'delivered_date': fields.get('delivered_date', ''),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
" "$ITEM_FILE"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_parse_item.sh`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/parse-item.sh tests/test_parse_item.sh
git commit -m "feat: add parse-item.sh with validation and tests"
```

---

## Task 3: create-item.sh — Create New Repair Items

**Files:**
- Create: `scripts/create-item.sh`
- Create: `tests/test_create_item.sh`

Depends on: `parse-item.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/test_create_item.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
    ((PASS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
}

# --- Test: create a basic item ---
test_create_basic() {
  setup
  local output
  output="$("$SCRIPT_DIR/create-item.sh" \
    --data-dir "$TEST_TMP/data" \
    --category camera \
    --brand Canon \
    --model "EOS R5" \
    --serial "012345678" \
    --owner-name "王小明" \
    --owner-contact "0912-345-678" \
    --description "觀景窗有霧氣" \
    --date "2026-03-22")"

  # Should output the created item ID
  assert_contains "$output" "CAM-20260322-EOS-R5-001" "should output correct ID"

  # Directory should exist
  assert_dir_exists "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001" "item dir should exist"

  # item.md should exist and be parseable
  assert_file_exists "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001/item.md" "item.md should exist"

  # logs/ should exist
  assert_dir_exists "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001/logs" "logs dir should exist"

  # Verify parseable
  "$SCRIPT_DIR/parse-item.sh" "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001/item.md" > /dev/null

  teardown
}

# --- Test: model name normalization ---
test_model_normalization() {
  setup
  local output
  output="$("$SCRIPT_DIR/create-item.sh" \
    --data-dir "$TEST_TMP/data" \
    --category lens \
    --brand Sony \
    --model "SEL 24-70 GM" \
    --serial "S123" \
    --owner-name "Test" \
    --owner-contact "test" \
    --description "Test" \
    --date "2026-03-22")"

  assert_contains "$output" "LENS-20260322-SEL-24-70-GM-001" "model should normalize correctly"
  assert_dir_exists "$TEST_TMP/data/repairs/LENS-20260322-SEL-24-70-GM-001" "normalized dir should exist"
  teardown
}

# --- Test: sequence number increments ---
test_sequence_increment() {
  setup
  # Create first item
  "$SCRIPT_DIR/create-item.sh" \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "A" --owner-contact "a" \
    --description "First" --date "2026-03-22" > /dev/null

  # Create second item with same type/date/model
  local output
  output="$("$SCRIPT_DIR/create-item.sh" \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "002" --owner-name "B" --owner-contact "b" \
    --description "Second" --date "2026-03-22")"

  assert_contains "$output" "CAM-20260322-EOS-R5-002" "second item should be 002"
  teardown
}

# --- Test: initial cost entry ---
test_initial_cost() {
  setup
  "$SCRIPT_DIR/create-item.sh" \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "A" --owner-contact "a" \
    --description "Test" --date "2026-03-22" \
    --cost-amount "3000" --cost-note "初步估價" > /dev/null

  local content
  content="$(cat "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001/item.md")"
  assert_contains "$content" "| 2026-03-22 | 3000 | 初步估價 |" "should contain cost entry"
  teardown
}

# --- Test: category prefix mapping ---
test_category_prefixes() {
  setup
  local output

  output="$("$SCRIPT_DIR/create-item.sh" --data-dir "$TEST_TMP/data" \
    --category accessory --brand Peak --model "Slide Lite" \
    --serial "A1" --owner-name "A" --owner-contact "a" \
    --description "T" --date "2026-03-22")"
  assert_contains "$output" "ACCE-" "accessory should use ACCE prefix"

  output="$("$SCRIPT_DIR/create-item.sh" --data-dir "$TEST_TMP/data" \
    --category misc --brand Other --model "Widget" \
    --serial "M1" --owner-name "A" --owner-contact "a" \
    --description "T" --date "2026-03-22")"
  assert_contains "$output" "OTH-" "misc should use OTH prefix"

  teardown
}

# --- Run all tests ---
echo "=== create-item.sh tests ==="
run_test "create basic item" test_create_basic
run_test "model normalization" test_model_normalization
run_test "sequence increment" test_sequence_increment
run_test "initial cost entry" test_initial_cost
run_test "category prefixes" test_category_prefixes

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_create_item.sh`
Expected: FAIL (create-item.sh does not exist yet)

- [ ] **Step 3: Implement create-item.sh**

```bash
#!/usr/bin/env bash
# scripts/create-item.sh — Create a new repair item
#
# Usage: create-item.sh --data-dir <dir> --category <cat> --brand <brand>
#        --model <model> --serial <sn> --owner-name <name> --owner-contact <contact>
#        --description <desc> --date <YYYY-MM-DD>
#        [--cost-amount <amount> --cost-note <note>]
#
# Output: the created item ID on stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse arguments ---
DATA_DIR="" CATEGORY="" BRAND="" MODEL="" SERIAL="" OWNER_NAME="" OWNER_CONTACT=""
DESCRIPTION="" DATE="" COST_AMOUNT="" COST_NOTE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --brand) BRAND="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    --owner-name) OWNER_NAME="$2"; shift 2 ;;
    --owner-contact) OWNER_CONTACT="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    --cost-amount) COST_AMOUNT="$2"; shift 2 ;;
    --cost-note) COST_NOTE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Validate required args ---
# (bash 3.2 compatible — no ${!var} indirect expansion)
for pair in "DATA_DIR:$DATA_DIR" "CATEGORY:$CATEGORY" "BRAND:$BRAND" "MODEL:$MODEL" \
            "SERIAL:$SERIAL" "OWNER_NAME:$OWNER_NAME" "OWNER_CONTACT:$OWNER_CONTACT" \
            "DESCRIPTION:$DESCRIPTION" "DATE:$DATE"; do
  var_name="${pair%%:*}"
  var_val="${pair#*:}"
  if [[ -z "$var_val" ]]; then
    echo "ERROR: Missing required argument --$(echo "$var_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')" >&2
    exit 1
  fi
done

# --- Map category to type prefix ---
case "$CATEGORY" in
  camera) TYPE_PREFIX="CAM" ;;
  lens) TYPE_PREFIX="LENS" ;;
  accessory) TYPE_PREFIX="ACCE" ;;
  misc) TYPE_PREFIX="OTH" ;;
  *) echo "ERROR: Invalid category '$CATEGORY'" >&2; exit 1 ;;
esac

# --- Normalize model name for ID ---
# Spaces become dashes, remove non-alphanumeric except dashes, preserve case
NORMALIZED_MODEL="$(echo "$MODEL" | sed 's/ /-/g' | sed 's/[^A-Za-z0-9-]//g')"

# --- Format date for ID (strip dashes) ---
DATE_COMPACT="${DATE//-/}"

# --- Determine sequence number ---
PREFIX="${TYPE_PREFIX}-${DATE_COMPACT}-${NORMALIZED_MODEL}"
SEQ=1
while [[ -d "$DATA_DIR/repairs/${PREFIX}-$(printf '%03d' $SEQ)" ]]; do
  ((SEQ++))
done
SEQ_PADDED="$(printf '%03d' $SEQ)"

ITEM_ID="${PREFIX}-${SEQ_PADDED}"
ITEM_DIR="$DATA_DIR/repairs/$ITEM_ID"

# --- Create directory structure ---
mkdir -p "$ITEM_DIR/logs"

# --- Build cost table content ---
COST_ROWS=""
if [[ -n "$COST_AMOUNT" && -n "$COST_NOTE" ]]; then
  COST_ROWS="| $DATE | $COST_AMOUNT | $COST_NOTE |"
fi

# --- Write item.md ---
# Use printf to avoid shell interpolation of user input (heredoc with unquoted
# delimiter would expand $, `, etc. in description/owner fields).
{
  printf '%s\n' "---"
  printf '%s\n' "id: $ITEM_ID"
  printf '%s\n' "category: $CATEGORY"
  printf '%s\n' "brand: $BRAND"
  printf '%s\n' "model: $MODEL"
  printf '%s\n' "serial_number: \"$SERIAL\""
  printf '%s\n' "status: not_started"
  printf '%s\n' "owner_name: $OWNER_NAME"
  printf '%s\n' "owner_contact: $OWNER_CONTACT"
  printf '%s\n' "received_date: $DATE"
  printf '%s\n' "delivered_date:"
  printf '%s\n' "---"
  printf '\n'
  printf '%s\n' "# 維修描述"
  printf '\n'
  printf '%s\n' "$DESCRIPTION"
  printf '\n'
  printf '%s\n' "# 費用紀錄"
  printf '\n'
  printf '%s\n' "| 日期 | 金額 | 說明 |"
  printf '%s\n' "|------|------|------|"
  [[ -n "$COST_ROWS" ]] && printf '%s\n' "$COST_ROWS"
} > "$ITEM_DIR/item.md"

# --- Validate the created file ---
"$SCRIPT_DIR/parse-item.sh" "$ITEM_DIR/item.md" > /dev/null

# --- Output the item ID ---
echo "$ITEM_ID"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_create_item.sh`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/create-item.sh tests/test_create_item.sh
git commit -m "feat: add create-item.sh with model normalization and sequencing"
```

---

## Task 4: update-item.sh — Update Existing Items

**Files:**
- Create: `scripts/update-item.sh`
- Create: `tests/test_update_item.sh`

Depends on: `parse-item.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/test_update_item.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
    ((PASS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
}

create_test_item() {
  local item_dir="$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001"
  mkdir -p "$item_dir/logs"
  cat > "$item_dir/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345678"
status: not_started
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

觀景窗有霧氣

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
| 2026-03-22 | 3000 | 初步估價 |
ITEM
  echo "$item_dir"
}

# --- Test: update status ---
test_update_status() {
  setup
  local item_dir
  item_dir="$(create_test_item)"

  "$SCRIPT_DIR/update-item.sh" \
    --item-dir "$item_dir" \
    --status "in_progress"

  local output
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md")"
  assert_contains "$output" '"status": "in_progress"' "status should be updated"
  teardown
}

# --- Test: update owner info ---
test_update_owner() {
  setup
  local item_dir
  item_dir="$(create_test_item)"

  "$SCRIPT_DIR/update-item.sh" \
    --item-dir "$item_dir" \
    --owner-name "李大華" \
    --owner-contact "IG: @lidahua"

  local output
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md")"
  assert_contains "$output" '"owner_name": "李大華"' "owner_name should be updated"
  assert_contains "$output" '"owner_contact": "IG: @lidahua"' "owner_contact should be updated"
  teardown
}

# --- Test: add cost entry ---
test_add_cost() {
  setup
  local item_dir
  item_dir="$(create_test_item)"

  "$SCRIPT_DIR/update-item.sh" \
    --item-dir "$item_dir" \
    --cost-amount "4500" \
    --cost-note "需更換快門組件" \
    --cost-date "2026-03-25"

  local content
  content="$(cat "$item_dir/item.md")"
  assert_contains "$content" "| 2026-03-22 | 3000 | 初步估價 |" "original cost should remain"
  assert_contains "$content" "| 2026-03-25 | 4500 | 需更換快門組件 |" "new cost should be appended"
  teardown
}

# --- Test: delivered sets delivered_date ---
test_delivered_sets_date() {
  setup
  local item_dir
  item_dir="$(create_test_item)"

  "$SCRIPT_DIR/update-item.sh" \
    --item-dir "$item_dir" \
    --status "delivered" \
    --delivered-date "2026-04-01"

  local output
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md")"
  assert_contains "$output" '"status": "delivered"' "status should be delivered"
  assert_contains "$output" '"delivered_date": "2026-04-01"' "delivered_date should be set"
  teardown
}

# --- Test: update description ---
test_update_description() {
  setup
  local item_dir
  item_dir="$(create_test_item)"

  "$SCRIPT_DIR/update-item.sh" \
    --item-dir "$item_dir" \
    --description "觀景窗有霧氣，快門異音，需拆機檢查"

  local content
  content="$(cat "$item_dir/item.md")"
  assert_contains "$content" "觀景窗有霧氣，快門異音，需拆機檢查" "description should be updated"
  teardown
}

# --- Run all tests ---
echo "=== update-item.sh tests ==="
run_test "update status" test_update_status
run_test "update owner" test_update_owner
run_test "add cost entry" test_add_cost
run_test "delivered sets date" test_delivered_sets_date
run_test "update description" test_update_description

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_update_item.sh`
Expected: FAIL

- [ ] **Step 3: Implement update-item.sh**

```bash
#!/usr/bin/env bash
# scripts/update-item.sh — Update an existing item's item.md
#
# Usage: update-item.sh --item-dir <dir> [--status <s>] [--owner-name <n>]
#        [--owner-contact <c>] [--description <d>] [--brand <b>] [--serial <s>]
#        [--cost-amount <a> --cost-note <n> --cost-date <d>]
#        [--delivered-date <d>]
#
# Only specified fields are updated; others remain unchanged.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse arguments ---
ITEM_DIR="" STATUS="" OWNER_NAME="" OWNER_CONTACT="" DESCRIPTION="" BRAND="" SERIAL=""
COST_AMOUNT="" COST_NOTE="" COST_DATE="" DELIVERED_DATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --item-dir) ITEM_DIR="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --owner-name) OWNER_NAME="$2"; shift 2 ;;
    --owner-contact) OWNER_CONTACT="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --brand) BRAND="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    --cost-amount) COST_AMOUNT="$2"; shift 2 ;;
    --cost-note) COST_NOTE="$2"; shift 2 ;;
    --cost-date) COST_DATE="$2"; shift 2 ;;
    --delivered-date) DELIVERED_DATE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$ITEM_DIR" ]] || { echo "ERROR: --item-dir is required" >&2; exit 1; }

ITEM_FILE="$ITEM_DIR/item.md"
[[ -f "$ITEM_FILE" ]] || { echo "ERROR: item.md not found in $ITEM_DIR" >&2; exit 1; }

# --- Read current file ---
CONTENT="$(cat "$ITEM_FILE")"

# --- Helper: replace a frontmatter field value ---
# Uses awk instead of sed to avoid delimiter collision with field values
replace_field() {
  local field="$1" new_value="$2"
  CONTENT="$(echo "$CONTENT" | awk -v f="$field" -v v="$new_value" '{
    if ($0 ~ "^"f":") print f": "v; else print
  }')"
}

# --- Apply field updates ---
[[ -n "$STATUS" ]] && replace_field "status" "$STATUS"
[[ -n "$OWNER_NAME" ]] && replace_field "owner_name" "$OWNER_NAME"
[[ -n "$OWNER_CONTACT" ]] && replace_field "owner_contact" "$OWNER_CONTACT"
[[ -n "$BRAND" ]] && replace_field "brand" "$BRAND"
[[ -n "$SERIAL" ]] && replace_field "serial_number" "\"$SERIAL\""
[[ -n "$DELIVERED_DATE" ]] && replace_field "delivered_date" "$DELIVERED_DATE"

# --- Update description ---
if [[ -n "$DESCRIPTION" ]]; then
  # Replace everything between "# 維修描述" and "# 費用紀錄"
  CONTENT="$(echo "$CONTENT" | awk -v desc="$DESCRIPTION" '
    /^# 維修描述/ { print; print ""; print desc; skip=1; next }
    /^# 費用紀錄/ { skip=0 }
    !skip { print }
  ')"
fi

# --- Append cost entry ---
if [[ -n "$COST_AMOUNT" && -n "$COST_NOTE" ]]; then
  COST_DATE="${COST_DATE:-$(date +%Y-%m-%d)}"
  COST_LINE="| $COST_DATE | $COST_AMOUNT | $COST_NOTE |"
  CONTENT="$(echo "$CONTENT")
$COST_LINE"
fi

# --- Write updated file ---
echo "$CONTENT" > "$ITEM_FILE"

# --- Validate ---
"$SCRIPT_DIR/parse-item.sh" "$ITEM_FILE" > /dev/null
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_update_item.sh`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/update-item.sh tests/test_update_item.sh
git commit -m "feat: add update-item.sh for partial field updates and cost appending"
```

---

## Task 5: update-owners.sh — Owner Registry Hook

**Files:**
- Create: `scripts/update-owners.sh`
- Create: `tests/test_update_owners.sh`

Depends on: `parse-item.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/test_update_owners.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
    ((PASS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
}

create_item_with_owner() {
  local data_dir="$1" id="$2" name="$3" contact="$4"
  local item_dir="$data_dir/repairs/$id"
  mkdir -p "$item_dir/logs"
  cat > "$item_dir/item.md" << ITEM
---
id: $id
category: camera
brand: Canon
model: EOS R5
serial_number: "001"
status: not_started
owner_name: $name
owner_contact: $contact
received_date: 2026-03-22
delivered_date:
---

# 維修描述

Test

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
ITEM
}

# --- Test: builds owners from items ---
test_builds_owners() {
  setup
  create_item_with_owner "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "王小明" "0912-345-678"
  create_item_with_owner "$TEST_TMP/data" "LENS-20260322-SEL-70200-001" "李大華" "IG: @lidahua"

  "$SCRIPT_DIR/update-owners.sh" "$TEST_TMP/data"

  local content
  content="$(cat "$TEST_TMP/data/owners.json")"
  assert_contains "$content" "王小明" "should contain first owner"
  assert_contains "$content" "李大華" "should contain second owner"
  assert_contains "$content" "0912-345-678" "should contain first contact"
  teardown
}

# --- Test: deduplicates on name+contact ---
test_dedup() {
  setup
  create_item_with_owner "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "王小明" "0912-345-678"
  create_item_with_owner "$TEST_TMP/data" "CAM-20260323-EOS-R6-001" "王小明" "0912-345-678"

  "$SCRIPT_DIR/update-owners.sh" "$TEST_TMP/data"

  local count
  count="$(grep -c "王小明" "$TEST_TMP/data/owners.json")"
  assert_eq "1" "$count" "duplicate owner should appear once"
  teardown
}

# --- Test: same name different contact kept separate ---
test_same_name_different_contact() {
  setup
  create_item_with_owner "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "王小明" "0912-345-678"
  create_item_with_owner "$TEST_TMP/data" "CAM-20260323-EOS-R6-001" "王小明" "IG: @wang"

  "$SCRIPT_DIR/update-owners.sh" "$TEST_TMP/data"

  local count
  count="$(grep -c "王小明" "$TEST_TMP/data/owners.json")"
  assert_eq "2" "$count" "same name with different contact should be two entries"
  teardown
}

# --- Run all tests ---
echo "=== update-owners.sh tests ==="
run_test "builds owners from items" test_builds_owners
run_test "deduplicates on name+contact" test_dedup
run_test "same name different contact" test_same_name_different_contact

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_update_owners.sh`
Expected: FAIL

- [ ] **Step 3: Implement update-owners.sh**

```bash
#!/usr/bin/env bash
# scripts/update-owners.sh — Rebuild owners.json from all item.md files
#
# Usage: update-owners.sh <data-dir>
# Scans all data/repairs/*/item.md, extracts owner_name + owner_contact,
# deduplicates on name+contact pair, writes to data/owners.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -eq 1 ]] || { echo "ERROR: Usage: update-owners.sh <data-dir>" >&2; exit 1; }

DATA_DIR="$1"
REPAIRS_DIR="$DATA_DIR/repairs"
OWNERS_FILE="$DATA_DIR/owners.json"

# Use Python to collect, deduplicate, and write JSON
# (bash 3.2 lacks associative arrays needed for dedup)
python3 -c "
import sys, json, os, subprocess

repairs_dir = sys.argv[1]
owners_file = sys.argv[2]
parse_script = sys.argv[3]

seen = set()
owners = []

if os.path.isdir(repairs_dir):
    for name in sorted(os.listdir(repairs_dir)):
        item_md = os.path.join(repairs_dir, name, 'item.md')
        if not os.path.isfile(item_md):
            continue
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)
        key = (item['owner_name'], item['owner_contact'])
        if key not in seen:
            seen.add(key)
            owners.append({'name': item['owner_name'], 'contact': item['owner_contact']})

with open(owners_file, 'w') as f:
    json.dump(owners, f, ensure_ascii=False, indent=2)
" "$REPAIRS_DIR" "$OWNERS_FILE" "$SCRIPT_DIR/parse-item.sh"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test_update_owners.sh`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/update-owners.sh tests/test_update_owners.sh
git commit -m "feat: add update-owners.sh hook for owner registry"
```

---

## Task 6: generate-dashboard.sh — Kanban Dashboard Generator

**Files:**
- Create: `scripts/generate-dashboard.sh`
- Create: `tests/test_generate_dashboard.sh`
- Create: `web/static/style.css` (shared styles)
- Create: `web/static/dashboard.js`

Depends on: `parse-item.sh`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/test_generate_dashboard.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
    ((PASS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
}

create_item() {
  local data_dir="$1" id="$2" status="$3" owner="$4" model="$5"
  local item_dir="$data_dir/repairs/$id"
  mkdir -p "$item_dir/logs"
  cat > "$item_dir/item.md" << ITEM
---
id: $id
category: camera
brand: Canon
model: $model
serial_number: "001"
status: $status
owner_name: $owner
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

Test

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
ITEM
}

# --- Test: generates dashboard.html ---
test_generates_html() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "not_started" "王小明" "EOS R5"
  create_item "$TEST_TMP/data" "LENS-20260322-SEL-70200-001" "in_progress" "李大華" "SEL 70-200"

  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  assert_file_exists "$TEST_TMP/web/dashboard.html" "dashboard.html should be created"

  local content
  content="$(cat "$TEST_TMP/web/dashboard.html")"
  assert_contains "$content" "CAM-20260322-EOS-R5-001" "should contain item ID"
  assert_contains "$content" "王小明" "should contain owner name"
  assert_contains "$content" "data-received" "should have data-received attribute"
  assert_contains "$content" "entry.html?id=" "cards should link to entry page"
  teardown
}

# --- Test: groups items by status ---
test_groups_by_status() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R5-001" "not_started" "A" "R5"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R6-001" "in_progress" "B" "R6"
  create_item "$TEST_TMP/data" "CAM-20260322-EOS-R7-001" "done" "C" "R7"

  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  local content
  content="$(cat "$TEST_TMP/web/dashboard.html")"
  assert_contains "$content" "未開始" "should have not_started column"
  assert_contains "$content" "進行中" "should have in_progress column"
  assert_contains "$content" "完成" "should have done column"
  teardown
}

# --- Test: empty state ---
test_empty_state() {
  setup
  mkdir -p "$TEST_TMP/web/static"

  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  assert_file_exists "$TEST_TMP/web/dashboard.html" "dashboard should be created even with no items"
  teardown
}

# --- Run all tests ---
echo "=== generate-dashboard.sh tests ==="
run_test "generates dashboard.html" test_generates_html
run_test "groups by status" test_groups_by_status
run_test "empty state" test_empty_state

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_generate_dashboard.sh`
Expected: FAIL

- [ ] **Step 3: Create web/static/style.css**

**CSS class contract** — the dashboard generator and entry page use these classes. All must be styled:

Dashboard classes: `toolbar`, `toolbar a`, `toolbar a.active`, `kanban`, `column`, `column-header`, `count`, `column-cards`, `card`, `card-id`, `card-model`, `card-owner`, `days-badge`, `empty-column`, `ice-box`, `ice-box.collapsed`, `section-toggle`, `section-cards`

Entry page classes: `entry-page`, `search-container`, `dropdown`, `search-result`, `suggestion`, `form-group`, `form-row`, `form-actions`, `cost-section`, `edit-mode`

```css
/* web/static/style.css — Shared styles for both pages */

/* --- Reset & Base --- */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: #f5f5f5;
  color: #333;
  line-height: 1.5;
}

/* --- Toolbar --- */
.toolbar {
  display: flex;
  gap: 0;
  background: #fff;
  border-bottom: 1px solid #ddd;
  padding: 0 24px;
}
.toolbar a {
  padding: 12px 20px;
  text-decoration: none;
  color: #666;
  font-weight: 500;
  border-bottom: 2px solid transparent;
}
.toolbar a.active {
  color: #333;
  border-bottom-color: #333;
}
.toolbar a:hover { color: #333; }

/* --- Kanban Dashboard --- */
.kanban {
  display: flex;
  gap: 16px;
  padding: 24px;
  overflow-x: auto;
  min-height: calc(100vh - 100px);
}
.column {
  flex: 1;
  min-width: 240px;
  background: #fff;
  border-radius: 8px;
  padding: 16px;
  border: 1px solid #e0e0e0;
}
.column-header {
  font-weight: 600;
  font-size: 14px;
  color: #555;
  margin-bottom: 12px;
  padding-bottom: 8px;
  border-bottom: 1px solid #eee;
}
.count { color: #999; font-weight: 400; }
.column-cards { display: flex; flex-direction: column; gap: 8px; }
.card {
  display: block;
  background: #fafafa;
  border: 1px solid #e8e8e8;
  border-radius: 6px;
  padding: 12px;
  text-decoration: none;
  color: inherit;
  cursor: pointer;
  transition: box-shadow 0.15s;
}
.card:hover {
  box-shadow: 0 2px 8px rgba(0,0,0,0.08);
  border-color: #ccc;
}
.card-id { font-size: 12px; color: #888; font-family: monospace; }
.card-model { font-weight: 600; margin: 4px 0; }
.card-owner { font-size: 13px; color: #666; }
.days-badge {
  display: inline-block;
  margin-top: 6px;
  font-size: 11px;
  color: #999;
  background: #f0f0f0;
  padding: 2px 8px;
  border-radius: 10px;
}
.empty-column { color: #ccc; text-align: center; padding: 20px; }

/* --- Ice Box --- */
.ice-box {
  margin: 0 24px 24px;
  background: #fff;
  border-radius: 8px;
  border: 1px solid #e0e0e0;
  padding: 16px;
}
.section-toggle {
  cursor: pointer;
  font-size: 16px;
  font-weight: 600;
  color: #555;
  user-select: none;
}
.section-toggle::before { content: "▼ "; font-size: 12px; }
.ice-box.collapsed .section-toggle::before { content: "▶ "; }
.ice-box.collapsed .section-cards { display: none; }
.section-cards {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 12px;
}
.section-cards .card { width: 240px; }

/* --- Entry Page --- */
.entry-page {
  max-width: 640px;
  margin: 24px auto;
  padding: 0 24px;
}
.search-container {
  position: relative;
  margin-bottom: 24px;
}
.search-container input {
  width: 100%;
  padding: 10px 14px;
  border: 1px solid #ddd;
  border-radius: 6px;
  font-size: 14px;
}
.dropdown {
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  background: #fff;
  border: 1px solid #ddd;
  border-radius: 0 0 6px 6px;
  max-height: 200px;
  overflow-y: auto;
  z-index: 10;
  box-shadow: 0 4px 12px rgba(0,0,0,0.1);
}
.search-result, .suggestion {
  padding: 8px 14px;
  cursor: pointer;
  font-size: 13px;
}
.search-result:hover, .suggestion:hover { background: #f5f5f5; }
.form-group {
  margin-bottom: 16px;
}
.form-group label {
  display: block;
  font-size: 13px;
  font-weight: 500;
  color: #555;
  margin-bottom: 4px;
}
.form-group input,
.form-group select,
.form-group textarea {
  width: 100%;
  padding: 8px 12px;
  border: 1px solid #ddd;
  border-radius: 6px;
  font-size: 14px;
  font-family: inherit;
}
.form-group textarea { resize: vertical; }
.form-row { display: flex; gap: 16px; }
.form-row .form-group { flex: 1; }
.cost-section {
  border: 1px solid #e0e0e0;
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
}
.cost-section legend {
  font-weight: 600;
  font-size: 14px;
  color: #555;
  padding: 0 8px;
}
#cost-history table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 12px;
  font-size: 13px;
}
#cost-history th, #cost-history td {
  padding: 6px 8px;
  border-bottom: 1px solid #eee;
  text-align: left;
}
#cost-history th { color: #888; font-weight: 500; }
.form-actions {
  display: flex;
  gap: 12px;
  justify-content: flex-end;
  margin-top: 24px;
}
.form-actions button {
  padding: 10px 24px;
  border: none;
  border-radius: 6px;
  font-size: 14px;
  cursor: pointer;
}
#submit-btn {
  background: #333;
  color: #fff;
}
#submit-btn:hover { background: #555; }
#open-logs-btn {
  background: #e8e8e8;
  color: #333;
}
#open-logs-btn:hover { background: #ddd; }
```

- [ ] **Step 4: Create web/static/dashboard.js**

```javascript
// web/static/dashboard.js — Compute days since received for each card

document.addEventListener('DOMContentLoaded', function() {
  const cards = document.querySelectorAll('[data-received]');
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  cards.forEach(function(card) {
    const received = new Date(card.getAttribute('data-received'));
    received.setHours(0, 0, 0, 0);
    const days = Math.floor((today - received) / (1000 * 60 * 60 * 24));
    const badge = card.querySelector('.days-badge');
    if (badge) {
      badge.textContent = days + ' 天';
    }
  });
});
```

- [ ] **Step 5: Implement generate-dashboard.sh**

```bash
#!/usr/bin/env bash
# scripts/generate-dashboard.sh — Generate kanban dashboard HTML
#
# Usage: generate-dashboard.sh <data-dir> <web-dir>
# Reads all items via parse-item.sh, groups by status,
# writes web/dashboard.html
#
# Uses Python for JSON parsing and HTML generation to avoid
# bash 4+ features (associative arrays, namerefs).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -eq 2 ]] || { echo "ERROR: Usage: generate-dashboard.sh <data-dir> <web-dir>" >&2; exit 1; }

DATA_DIR="$1"
WEB_DIR="$2"

python3 -c "
import sys, json, os, subprocess

repairs_dir = os.path.join(sys.argv[1], 'repairs')
web_dir = sys.argv[2]
parse_script = sys.argv[3]

# Collect items grouped by status
groups = {
    'not_started': [],
    'in_progress': [],
    'testing': [],
    'done': [],
    'ice_box': [],
    'delivered': [],
}

if os.path.isdir(repairs_dir):
    for name in sorted(os.listdir(repairs_dir)):
        item_md = os.path.join(repairs_dir, name, 'item.md')
        if not os.path.isfile(item_md):
            continue
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)
        status = item.get('status', '')
        if status in groups:
            groups[status].append(item)

def render_card(item):
    return (
        f'<a class=\"card\" href=\"entry.html?id={item[\"id\"]}\" data-received=\"{item[\"received_date\"]}\">'
        f'<div class=\"card-id\">{item[\"id\"]}</div>'
        f'<div class=\"card-model\">{item[\"model\"]}</div>'
        f'<div class=\"card-owner\">{item[\"owner_name\"]}</div>'
        f'<div class=\"days-badge\"></div>'
        f'</a>'
    )

def render_cards(items):
    if not items:
        return '<div class=\"empty-column\">\u2014</div>'
    return '\n'.join(render_card(item) for item in items)

columns = [
    ('not_started', '未開始'),
    ('in_progress', '進行中'),
    ('testing', '測試中'),
    ('done', '完成\u30FB待取件'),
]

columns_html = ''
for status, label in columns:
    items = groups[status]
    columns_html += f'''
    <div class=\"column\">
      <div class=\"column-header\">{label} <span class=\"count\">({len(items)})</span></div>
      <div class=\"column-cards\">
        {render_cards(items)}
      </div>
    </div>'''

ice_items = groups['ice_box']
ice_html = render_cards(ice_items)

html = f'''<!DOCTYPE html>
<html lang=\"zh-Hant\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>維修進度看板</title>
  <link rel=\"stylesheet\" href=\"static/style.css\">
</head>
<body>
  <nav class=\"toolbar\">
    <a href=\"entry.html\">維修單</a>
    <a href=\"dashboard.html\" class=\"active\">看板</a>
  </nav>
  <main class=\"kanban\">{columns_html}
  </main>
  <section class=\"ice-box collapsed\">
    <h2 class=\"section-toggle\" onclick=\"this.parentElement.classList.toggle(\'collapsed\')\">
      冰箱 <span class=\"count\">({len(ice_items)})</span>
    </h2>
    <div class=\"section-cards\">
      {ice_html}
    </div>
  </section>
  <script src=\"static/dashboard.js\"></script>
</body>
</html>'''

os.makedirs(web_dir, exist_ok=True)
with open(os.path.join(web_dir, 'dashboard.html'), 'w') as f:
    f.write(html)
" "$DATA_DIR" "$WEB_DIR" "$SCRIPT_DIR/parse-item.sh"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test_generate_dashboard.sh`
Expected: All 3 tests PASS

- [ ] **Step 7: Commit**

```bash
git add scripts/generate-dashboard.sh tests/test_generate_dashboard.sh web/static/style.css web/static/dashboard.js
git commit -m "feat: add dashboard generator with kanban layout and client-side day computation"
```

---

## Task 7: server.py and server.sh — HTTP Server

**Files:**
- Create: `scripts/server.py`
- Create: `scripts/server.sh`
- Create: `tests/test_server.sh`

Depends on: all scripts from Tasks 2-6

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# tests/test_server.sh — Integration tests for the HTTP server

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

PASS_COUNT=0
FAIL_COUNT=0
SERVER_PID=""

run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
    ((PASS_COUNT++))
  else
    ((FAIL_COUNT++))
  fi
}

start_server() {
  mkdir -p "$TEST_TMP/web/static"

  # Generate initial dashboard
  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  # Copy static assets
  cp "$SCRIPT_DIR/../web/entry.html" "$TEST_TMP/web/" 2>/dev/null || true
  cp "$SCRIPT_DIR/../web/static/"* "$TEST_TMP/web/static/" 2>/dev/null || true

  # Start server on a random available port
  TEST_PORT=18787
  python3 "$SCRIPT_DIR/server.py" \
    --port "$TEST_PORT" \
    --data-dir "$TEST_TMP/data" \
    --web-dir "$TEST_TMP/web" \
    --scripts-dir "$SCRIPT_DIR" &
  SERVER_PID=$!
  # Wait for server to be ready (retry up to 5 seconds)
  for i in $(seq 1 50); do
    if curl -s -o /dev/null "http://localhost:$TEST_PORT/" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo "ERROR: Server failed to start within 5 seconds" >&2
  return 1
}

stop_server() {
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
}

# --- Test: GET / serves dashboard ---
test_get_dashboard() {
  setup
  start_server
  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$TEST_PORT/")"
  assert_eq "200" "$status" "GET / should return 200"
  stop_server
  teardown
}

# --- Test: POST /api/create creates an item ---
test_create_item() {
  setup
  start_server
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/create" \
    -H "Content-Type: application/json" \
    -d '{
      "category": "camera",
      "brand": "Canon",
      "model": "EOS R5",
      "serial_number": "012345678",
      "owner_name": "王小明",
      "owner_contact": "0912-345-678",
      "description": "觀景窗有霧氣",
      "date": "2026-03-22"
    }')"
  assert_contains "$response" "CAM-20260322-EOS-R5-001" "should return created item ID"
  assert_dir_exists "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001" "item dir should exist"
  stop_server
  teardown
}

# --- Test: GET /api/items returns item list ---
test_get_items() {
  setup
  "$SCRIPT_DIR/create-item.sh" --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  start_server
  local response
  response="$(curl -s "http://localhost:$TEST_PORT/api/items")"
  assert_contains "$response" "CAM-20260322-EOS-R5-001" "items should include created item"
  stop_server
  teardown
}

# --- Test: GET /api/owners returns owners ---
test_get_owners() {
  setup
  "$SCRIPT_DIR/create-item.sh" --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  "$SCRIPT_DIR/update-owners.sh" "$TEST_TMP/data"
  start_server
  local response
  response="$(curl -s "http://localhost:$TEST_PORT/api/owners")"
  assert_contains "$response" "王小明" "owners should include the owner"
  stop_server
  teardown
}

# --- Test: GET /api/item/<id>/raw returns raw markdown ---
test_get_item_raw() {
  setup
  "$SCRIPT_DIR/create-item.sh" --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  start_server
  local response
  response="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$response" "# 維修描述" "raw should include markdown body"
  assert_contains "$response" "owner_name: 王小明" "raw should include frontmatter"
  stop_server
  teardown
}

# --- Run all tests ---
echo "=== server.py tests ==="
run_test "GET / serves dashboard" test_get_dashboard
run_test "POST /api/create" test_create_item
run_test "GET /api/items" test_get_items
run_test "GET /api/owners" test_get_owners
run_test "GET /api/item/<id>/raw" test_get_item_raw

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test_server.sh`
Expected: FAIL

- [ ] **Step 3: Implement server.py**

```python
#!/usr/bin/env python3
"""HTTP server for the camera repair shop inventory system.

Uses only Python standard library. Serves static files from web/ and
handles API endpoints by calling shell scripts.

Usage: python3 server.py --port 8787 --data-dir data --web-dir web --scripts-dir scripts
"""

import argparse
import json
import os
import subprocess
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


class InventoryHandler(SimpleHTTPRequestHandler):
    """Custom handler for the inventory system."""

    def __init__(self, *args, data_dir, web_dir, scripts_dir, **kwargs):
        self.data_dir = data_dir
        self.web_dir = web_dir
        self.scripts_dir = scripts_dir
        super().__init__(*args, directory=web_dir, **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/' or path == '':
            # Serve dashboard.html as landing page
            self.path = '/dashboard.html'
            return super().do_GET()
        elif path == '/api/items':
            self._handle_get_items()
        elif path == '/api/owners':
            self._handle_get_owners()
        elif path.startswith('/api/item/') and path.endswith('/raw'):
            item_id = path[len('/api/item/'):-len('/raw')]
            self._handle_get_item_raw(item_id)
        elif path.startswith('/api/open-logs/'):
            item_id = path[len('/api/open-logs/'):]
            self._handle_open_logs(item_id)
        else:
            super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            self._send_json(400, {'error': 'Invalid JSON'})
            return

        if path == '/api/create':
            self._handle_create(data)
        elif path == '/api/update':
            self._handle_update(data)
        elif path == '/api/deliver':
            self._handle_deliver(data)
        else:
            self._send_json(404, {'error': 'Not found'})

    def _handle_get_items(self):
        """Return all items as JSON (frontmatter only)."""
        repairs_dir = os.path.join(self.data_dir, 'repairs')
        items = []
        if os.path.isdir(repairs_dir):
            for name in sorted(os.listdir(repairs_dir)):
                item_md = os.path.join(repairs_dir, name, 'item.md')
                if os.path.isfile(item_md):
                    result = subprocess.run(
                        [os.path.join(self.scripts_dir, 'parse-item.sh'), item_md],
                        capture_output=True, text=True
                    )
                    if result.returncode == 0:
                        items.append(json.loads(result.stdout))
        self._send_json(200, items)

    def _handle_get_owners(self):
        """Return owners.json."""
        owners_file = os.path.join(self.data_dir, 'owners.json')
        if os.path.isfile(owners_file):
            with open(owners_file, 'r') as f:
                self._send_json(200, json.load(f))
        else:
            self._send_json(200, [])

    def _handle_get_item_raw(self, item_id):
        """Return raw item.md content."""
        item_md = os.path.join(self.data_dir, 'repairs', item_id, 'item.md')
        if os.path.isfile(item_md):
            with open(item_md, 'r') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/markdown; charset=utf-8')
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))
        else:
            self._send_json(404, {'error': f'Item not found: {item_id}'})

    def _handle_open_logs(self, item_id):
        """Open the item's logs folder in Finder."""
        logs_dir = os.path.join(self.data_dir, 'repairs', item_id, 'logs')
        if os.path.isdir(logs_dir):
            subprocess.Popen(['open', logs_dir])
            self._send_json(200, {'ok': True})
        else:
            self._send_json(404, {'error': f'Logs folder not found: {item_id}'})

    def _handle_create(self, data):
        """Create a new repair item."""
        cmd = [
            os.path.join(self.scripts_dir, 'create-item.sh'),
            '--data-dir', self.data_dir,
            '--category', data.get('category', ''),
            '--brand', data.get('brand', ''),
            '--model', data.get('model', ''),
            '--serial', data.get('serial_number', ''),
            '--owner-name', data.get('owner_name', ''),
            '--owner-contact', data.get('owner_contact', ''),
            '--description', data.get('description', ''),
            '--date', data.get('date', ''),
        ]
        if data.get('cost_amount') and data.get('cost_note'):
            cmd += ['--cost-amount', str(data['cost_amount']), '--cost-note', data['cost_note']]

        # Default date to today if not provided
        if not data.get('date'):
            from datetime import date
            cmd[cmd.index('--date') + 1] = date.today().isoformat()

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            item_id = result.stdout.strip()
            # Run hooks
            self._run_hooks(item_id)
            self._send_json(200, {'id': item_id})
        else:
            self._send_json(400, {'error': result.stderr.strip()})

    def _handle_update(self, data):
        """Update an existing item."""
        item_id = data.get('id', '')
        item_dir = os.path.join(self.data_dir, 'repairs', item_id)

        if not os.path.isdir(item_dir):
            self._send_json(404, {'error': f'Item not found: {item_id}'})
            return

        cmd = [os.path.join(self.scripts_dir, 'update-item.sh'), '--item-dir', item_dir]

        field_map = {
            'status': '--status',
            'owner_name': '--owner-name',
            'owner_contact': '--owner-contact',
            'description': '--description',
            'brand': '--brand',
            'serial_number': '--serial',
        }
        for field, flag in field_map.items():
            if field in data and data[field]:
                cmd += [flag, str(data[field])]

        if data.get('cost_amount') and data.get('cost_note'):
            cmd += [
                '--cost-amount', str(data['cost_amount']),
                '--cost-note', data['cost_note'],
                '--cost-date', data.get('cost_date', ''),
            ]

        if data.get('delivered_date'):
            cmd += ['--delivered-date', data['delivered_date']]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            self._run_hooks(item_id)
            self._send_json(200, {'ok': True, 'id': item_id})
        else:
            self._send_json(400, {'error': result.stderr.strip()})

    def _handle_deliver(self, data):
        """Mark an item as delivered."""
        data['status'] = 'delivered'
        if 'delivered_date' not in data:
            from datetime import date
            data['delivered_date'] = date.today().isoformat()
        self._handle_update(data)

    def _run_hooks(self, item_id):
        """Run post-mutation hooks: update owners, regenerate dashboard."""
        subprocess.run(
            [os.path.join(self.scripts_dir, 'update-owners.sh'), self.data_dir],
            capture_output=True, text=True
        )
        web_dir = self.web_dir
        subprocess.run(
            [os.path.join(self.scripts_dir, 'generate-dashboard.sh'), self.data_dir, web_dir],
            capture_output=True, text=True
        )

    def _send_json(self, status_code, data):
        """Send a JSON response."""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))


def make_handler(data_dir, web_dir, scripts_dir):
    """Create a handler class with the given directories."""
    def handler(*args, **kwargs):
        return InventoryHandler(
            *args,
            data_dir=data_dir,
            web_dir=web_dir,
            scripts_dir=scripts_dir,
            **kwargs
        )
    return handler


def main():
    parser = argparse.ArgumentParser(description='Camera Repair Inventory Server')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--data-dir', default='data')
    parser.add_argument('--web-dir', default='web')
    parser.add_argument('--scripts-dir', default='scripts')
    args = parser.parse_args()

    # Resolve to absolute paths
    data_dir = os.path.abspath(args.data_dir)
    web_dir = os.path.abspath(args.web_dir)
    scripts_dir = os.path.abspath(args.scripts_dir)

    handler = make_handler(data_dir, web_dir, scripts_dir)
    server = HTTPServer(('127.0.0.1', args.port), handler)

    print(f"Server running at http://localhost:{args.port}")
    print(f"  Data: {data_dir}")
    print(f"  Web:  {web_dir}")
    print(f"Press Ctrl+C to stop.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()


if __name__ == '__main__':
    main()
```

- [ ] **Step 4: Implement server.sh**

```bash
#!/usr/bin/env bash
# scripts/server.sh — One-command start for the inventory server
#
# Usage: ./scripts/server.sh
# Checks for Python 3, kills any existing process on port 8787, starts the server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT=8787

# --- Check Python 3 ---
if ! command -v python3 &>/dev/null; then
  echo "ERROR: Python 3 is required but not found." >&2
  echo "macOS should have it pre-installed. Try: xcode-select --install" >&2
  exit 1
fi

# --- Kill existing process on port ---
existing_pid="$(lsof -ti :$PORT 2>/dev/null || true)"
if [[ -n "$existing_pid" ]]; then
  echo "Killing existing process on port $PORT (PID: $existing_pid)"
  kill "$existing_pid" 2>/dev/null || true
  sleep 1
fi

# --- Ensure data directories exist ---
mkdir -p "$PROJECT_DIR/data/repairs"
[[ -f "$PROJECT_DIR/data/owners.json" ]] || echo '[]' > "$PROJECT_DIR/data/owners.json"

# --- Generate initial dashboard if missing ---
if [[ ! -f "$PROJECT_DIR/web/dashboard.html" ]]; then
  echo "Generating initial dashboard..."
  "$SCRIPT_DIR/generate-dashboard.sh" "$PROJECT_DIR/data" "$PROJECT_DIR/web"
fi

# --- Start server ---
echo "Starting server on http://localhost:$PORT"
python3 "$SCRIPT_DIR/server.py" \
  --port "$PORT" \
  --data-dir "$PROJECT_DIR/data" \
  --web-dir "$PROJECT_DIR/web" \
  --scripts-dir "$SCRIPT_DIR"
```

- [ ] **Step 5: Make scripts executable**

```bash
chmod +x scripts/server.sh scripts/server.py scripts/create-item.sh scripts/update-item.sh scripts/parse-item.sh scripts/update-owners.sh scripts/generate-dashboard.sh
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test_server.sh`
Expected: All 5 tests PASS

- [ ] **Step 7: Commit**

```bash
git add scripts/server.py scripts/server.sh tests/test_server.sh
git commit -m "feat: add HTTP server with API endpoints and one-command startup"
```

---

## Task 8: Entry Page — Static HTML with JS

**Files:**
- Create: `web/entry.html`
- Create: `web/static/entry.js`

Depends on: server.py (API endpoints), style.css

This is the main form page. It's a static HTML file with JS that handles:
- Create mode (default): blank form
- Edit mode (`?id=...`): fetches raw item.md, parses frontmatter + body, populates form
- Search bar with client-side filtering from `/api/items`
- Owner autocomplete from `/api/owners`
- Cost editing with change log generation
- "Open logs folder" button in edit mode

- [ ] **Step 1: Create web/entry.html**

**IMPORTANT:** entry.js references the following element IDs. The HTML MUST use exactly these IDs:

| Element ID | Element Type | Purpose |
|------------|-------------|---------|
| `search` | `<input>` | Search bar for finding existing items |
| `search-results` | `<div>` | Dropdown for search results |
| `repair-form` | `<form>` | Main form element |
| `category` | `<select>` | Category dropdown |
| `brand` | `<input>` | Brand text field |
| `model` | `<input>` | Model text field |
| `serial` | `<input>` | Serial number text field |
| `owner-name` | `<input>` | Owner name with autocomplete |
| `owner-contact` | `<input>` | Owner contact text field |
| `owner-suggestions` | `<div>` | Owner autocomplete dropdown |
| `description` | `<textarea>` | Repair description |
| `status` | `<select>` | Status dropdown (edit mode) |
| `status-group` | `<div>` | Container for status field (hidden in create mode) |
| `cost-amount` | `<input>` | Cost amount field |
| `cost-note` | `<input>` | Cost note/reason field |
| `cost-history` | `<div>` | Cost history table (edit mode) |
| `open-logs-btn` | `<button>` | "Open logs folder" button (edit mode) |
| `submit-btn` | `<button>` | Form submit button |

```html
<!DOCTYPE html>
<html lang="zh-Hant">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>建立/編輯維修單</title>
  <link rel="stylesheet" href="static/style.css">
</head>
<body>
  <nav class="toolbar">
    <a href="entry.html" class="active">維修單</a>
    <a href="dashboard.html">看板</a>
  </nav>

  <main class="entry-page">
    <div class="search-container">
      <input type="text" id="search" placeholder="搜尋維修單（ID、型號、客戶名稱）..." autocomplete="off">
      <div id="search-results" class="dropdown" style="display:none"></div>
    </div>

    <form id="repair-form">
      <div class="form-group">
        <label for="category">類別</label>
        <select id="category" required>
          <option value="">請選擇...</option>
          <option value="camera">相機</option>
          <option value="lens">鏡頭</option>
          <option value="accessory">配件</option>
          <option value="misc">其他</option>
        </select>
      </div>

      <div class="form-group">
        <label for="brand">品牌</label>
        <input type="text" id="brand" required>
      </div>

      <div class="form-group">
        <label for="model">型號</label>
        <input type="text" id="model" required>
      </div>

      <div class="form-group">
        <label for="serial">序號</label>
        <input type="text" id="serial" required>
      </div>

      <div class="form-group" style="position:relative">
        <label for="owner-name">客戶姓名</label>
        <input type="text" id="owner-name" required autocomplete="off">
        <div id="owner-suggestions" class="dropdown" style="display:none"></div>
      </div>

      <div class="form-group">
        <label for="owner-contact">聯絡方式</label>
        <input type="text" id="owner-contact" required placeholder="電話、IG、FB...">
      </div>

      <div class="form-group">
        <label for="description">維修描述</label>
        <textarea id="description" rows="4" required></textarea>
      </div>

      <div id="status-group" class="form-group" style="display:none">
        <label for="status">狀態</label>
        <select id="status">
          <option value="not_started">未開始</option>
          <option value="in_progress">進行中</option>
          <option value="testing">測試中</option>
          <option value="done">完成</option>
          <option value="delivered">已交付</option>
          <option value="ice_box">冰箱</option>
        </select>
      </div>

      <fieldset class="cost-section">
        <legend>費用</legend>
        <div id="cost-history"></div>
        <div class="form-row">
          <div class="form-group">
            <label for="cost-amount">金額</label>
            <input type="number" id="cost-amount">
          </div>
          <div class="form-group">
            <label for="cost-note">說明</label>
            <input type="text" id="cost-note" placeholder="估價、零件費用...">
          </div>
        </div>
      </fieldset>

      <div class="form-actions">
        <button type="button" id="open-logs-btn" style="display:none">開啟維修記錄資料夾</button>
        <button type="submit" id="submit-btn">建立維修單</button>
      </div>
    </form>
  </main>

  <script src="static/entry.js"></script>
</body>
</html>
```

- [ ] **Step 2: Create web/static/entry.js**

Implement all client-side logic:

```javascript
// web/static/entry.js — Entry page logic

(function() {
  'use strict';

  let allItems = [];
  let allOwners = [];
  let currentItemId = null;
  let originalCost = null;

  // --- Init ---
  document.addEventListener('DOMContentLoaded', async function() {
    await Promise.all([loadItems(), loadOwners()]);
    checkEditMode();
    setupSearch();
    setupOwnerAutocomplete();
    setupForm();
  });

  // --- Load data ---
  async function loadItems() {
    const res = await fetch('/api/items');
    allItems = await res.json();
  }

  async function loadOwners() {
    const res = await fetch('/api/owners');
    allOwners = await res.json();
  }

  // --- Edit mode via query param ---
  function checkEditMode() {
    const params = new URLSearchParams(window.location.search);
    const id = params.get('id');
    if (id) {
      loadItemForEdit(id);
    }
  }

  async function loadItemForEdit(id) {
    const res = await fetch('/api/item/' + encodeURIComponent(id) + '/raw');
    if (!res.ok) {
      alert('找不到維修單: ' + id);
      return;
    }
    const markdown = await res.text();
    const parsed = parseItemMarkdown(markdown);
    currentItemId = id;
    populateForm(parsed);
    showEditMode();
  }

  // --- Parse item.md in JS ---
  function parseItemMarkdown(md) {
    const result = { frontmatter: {}, description: '', costRows: [] };

    // Extract frontmatter
    const fmMatch = md.match(/^---\n([\s\S]*?)\n---/);
    if (fmMatch) {
      fmMatch[1].split('\n').forEach(function(line) {
        const colonIdx = line.indexOf(':');
        if (colonIdx > 0) {
          const key = line.substring(0, colonIdx).trim();
          let value = line.substring(colonIdx + 1).trim();
          // Remove surrounding quotes
          if (value.startsWith('"') && value.endsWith('"')) {
            value = value.slice(1, -1);
          }
          result.frontmatter[key] = value;
        }
      });
    }

    // Extract description
    const descMatch = md.match(/# 維修描述\n\n([\s\S]*?)(?=\n# |$)/);
    if (descMatch) {
      result.description = descMatch[1].trim();
    }

    // Extract cost rows
    const costMatch = md.match(/# 費用紀錄\n\n\| 日期[\s\S]*?\n\|[-|\s]+\n([\s\S]*?)$/);
    if (costMatch) {
      costMatch[1].trim().split('\n').forEach(function(line) {
        if (line.startsWith('|')) {
          const cells = line.split('|').map(function(c) { return c.trim(); }).filter(Boolean);
          if (cells.length === 3) {
            result.costRows.push({ date: cells[0], amount: cells[1], note: cells[2] });
          }
        }
      });
    }

    return result;
  }

  function populateForm(parsed) {
    const fm = parsed.frontmatter;
    document.getElementById('category').value = fm.category || '';
    document.getElementById('brand').value = fm.brand || '';
    document.getElementById('model').value = fm.model || '';
    document.getElementById('serial').value = fm.serial_number || '';
    document.getElementById('owner-name').value = fm.owner_name || '';
    document.getElementById('owner-contact').value = fm.owner_contact || '';
    document.getElementById('description').value = parsed.description || '';
    document.getElementById('status').value = fm.status || '';

    // Display cost history
    originalCost = { amount: '', note: '' };
    const lastRow = parsed.costRows[parsed.costRows.length - 1];
    if (lastRow) {
      document.getElementById('cost-amount').value = lastRow.amount;
      document.getElementById('cost-note').value = lastRow.note;
      originalCost = { amount: lastRow.amount, note: lastRow.note };
    }
    renderCostHistory(parsed.costRows);
  }

  function renderCostHistory(rows) {
    const container = document.getElementById('cost-history');
    if (!container || rows.length === 0) return;
    let html = '<table><thead><tr><th>日期</th><th>金額</th><th>說明</th></tr></thead><tbody>';
    rows.forEach(function(r) {
      html += '<tr><td>' + r.date + '</td><td>' + r.amount + '</td><td>' + r.note + '</td></tr>';
    });
    html += '</tbody></table>';
    container.innerHTML = html;
  }

  function showEditMode() {
    document.body.classList.add('edit-mode');
    document.getElementById('status-group').style.display = '';
    document.getElementById('open-logs-btn').style.display = '';
    document.getElementById('submit-btn').textContent = '更新維修單';
  }

  // --- Search ---
  function setupSearch() {
    const input = document.getElementById('search');
    const results = document.getElementById('search-results');
    if (!input || !results) return;

    input.addEventListener('input', function() {
      const q = input.value.toLowerCase();
      if (q.length < 1) {
        results.style.display = 'none';
        return;
      }
      const matches = allItems.filter(function(item) {
        return item.id.toLowerCase().includes(q) ||
               item.model.toLowerCase().includes(q) ||
               item.owner_name.toLowerCase().includes(q);
      });
      if (matches.length === 0) {
        results.style.display = 'none';
        return;
      }
      results.innerHTML = matches.map(function(item) {
        return '<div class="search-result" data-id="' + item.id + '">' +
               item.id + ' — ' + item.model + ' (' + item.owner_name + ')</div>';
      }).join('');
      results.style.display = '';

      results.querySelectorAll('.search-result').forEach(function(el) {
        el.addEventListener('click', function() {
          window.location.href = 'entry.html?id=' + el.dataset.id;
        });
      });
    });
  }

  // --- Owner autocomplete ---
  function setupOwnerAutocomplete() {
    const nameInput = document.getElementById('owner-name');
    const contactInput = document.getElementById('owner-contact');
    const suggestions = document.getElementById('owner-suggestions');
    if (!nameInput || !suggestions) return;

    nameInput.addEventListener('input', function() {
      const q = nameInput.value.toLowerCase();
      if (q.length < 1) {
        suggestions.style.display = 'none';
        return;
      }
      const matches = allOwners.filter(function(o) {
        return o.name.toLowerCase().includes(q) || o.contact.toLowerCase().includes(q);
      });
      if (matches.length === 0) {
        suggestions.style.display = 'none';
        return;
      }
      suggestions.innerHTML = matches.map(function(o, i) {
        return '<div class="suggestion" data-idx="' + i + '">' +
               o.name + ' — ' + o.contact + '</div>';
      }).join('');
      suggestions.style.display = '';

      suggestions.querySelectorAll('.suggestion').forEach(function(el) {
        el.addEventListener('click', function() {
          const match = matches[parseInt(el.dataset.idx)];
          nameInput.value = match.name;
          contactInput.value = match.contact;
          suggestions.style.display = 'none';
        });
      });
    });
  }

  // --- Form submission ---
  function setupForm() {
    const form = document.getElementById('repair-form');
    if (!form) return;

    form.addEventListener('submit', async function(e) {
      e.preventDefault();

      if (currentItemId) {
        await submitUpdate();
      } else {
        await submitCreate();
      }
    });

    // Open logs button
    const logsBtn = document.getElementById('open-logs-btn');
    if (logsBtn) {
      logsBtn.addEventListener('click', function() {
        if (currentItemId) {
          fetch('/api/open-logs/' + encodeURIComponent(currentItemId));
        }
      });
    }
  }

  async function submitCreate() {
    const data = {
      category: document.getElementById('category').value,
      brand: document.getElementById('brand').value,
      model: document.getElementById('model').value,
      serial_number: document.getElementById('serial').value,
      owner_name: document.getElementById('owner-name').value,
      owner_contact: document.getElementById('owner-contact').value,
      description: document.getElementById('description').value,
      date: new Date().toISOString().split('T')[0],
    };

    const amount = document.getElementById('cost-amount').value;
    const note = document.getElementById('cost-note').value;
    if (amount && note) {
      data.cost_amount = amount;
      data.cost_note = note;
    }

    const res = await fetch('/api/create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    const result = await res.json();
    if (res.ok) {
      window.location.href = 'entry.html?id=' + result.id;
    } else {
      alert('建立失敗: ' + result.error);
    }
  }

  async function submitUpdate() {
    const data = {
      id: currentItemId,
      status: document.getElementById('status').value,
      owner_name: document.getElementById('owner-name').value,
      owner_contact: document.getElementById('owner-contact').value,
      description: document.getElementById('description').value,
      brand: document.getElementById('brand').value,
      serial_number: document.getElementById('serial').value,
    };

    // Check if cost changed — if so, append a cost change log entry
    const newAmount = document.getElementById('cost-amount').value;
    const newNote = document.getElementById('cost-note').value;
    if (originalCost && (newAmount !== originalCost.amount || newNote !== originalCost.note)) {
      data.cost_amount = newAmount;
      data.cost_note = newNote;
      data.cost_date = new Date().toISOString().split('T')[0];
    }

    // Auto-set delivered_date
    if (data.status === 'delivered') {
      data.delivered_date = new Date().toISOString().split('T')[0];
    }

    const res = await fetch('/api/update', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    const result = await res.json();
    if (res.ok) {
      // Reload to show updated data
      window.location.reload();
    } else {
      alert('更新失敗: ' + result.error);
    }
  }
})();
```

- [ ] **Step 3: Manual test**

Run: `./scripts/server.sh`
- Open `http://localhost:8787/entry.html` — verify create form renders
- Create an item — verify redirect to edit mode
- Open `http://localhost:8787/` — verify dashboard shows the item
- Click the card — verify entry page loads in edit mode
- Update status — verify it saves

- [ ] **Step 4: Commit**

```bash
git add web/entry.html web/static/entry.js
git commit -m "feat: add entry page with create/edit form, search, and owner autocomplete"
```

---

## Task 9: Documentation and Final Polish

**Files:**
- Create: `docs/format.md`
- Modify: `web/static/style.css` (polish)

- [ ] **Step 1: Write docs/format.md**

Document the `item.md` schema for humans and agents:
- Frontmatter fields with types and allowed values
- Body section format (headings, cost table structure)
- ID format and normalization rules
- Status values and lifecycle
- Example complete `item.md`

- [ ] **Step 2: Final CSS polish**

Review and refine `web/static/style.css` for:
- Toolbar active state styling
- Kanban column layout and card hover effects
- Form field alignment and spacing
- Search results and autocomplete dropdown styling
- Ice box collapsed/expanded toggle
- Responsive within reasonable desktop widths

- [ ] **Step 3: End-to-end manual test**

Full walkthrough:
1. `./scripts/server.sh` — starts cleanly
2. Create 3-4 items with different categories
3. Verify dashboard shows all items in correct columns
4. Edit items: change status, add costs
5. Verify dashboard updates after edits
6. Test owner autocomplete on second item with same owner
7. Open logs folder from edit page
8. Mark an item as delivered — verify it leaves the board

- [ ] **Step 4: Commit**

```bash
git add docs/format.md web/static/style.css
git commit -m "docs: add item.md format documentation and polish CSS"
```
