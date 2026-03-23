#!/usr/bin/env bash
# tests/test_generate_dashboard.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"


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

test_dashboard_from_nested_dirs() {
  setup
  mkdir -p "$TEST_TMP/web"
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name "王小明" --owner-contact "0912" --description "test" --date 2026-03-22
  "$SCRIPT_DIR/generate-dashboard.sh" "$TEST_TMP/data" "$TEST_TMP/web"
  DASHBOARD="$(cat "$TEST_TMP/web/dashboard.html")"
  assert_contains "$DASHBOARD" "王小明" "owner appears in dashboard from nested dir"
  teardown
}

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

# --- Run all tests ---
echo "=== generate-dashboard.sh tests ==="
run_test "generates dashboard.html" test_generates_html
run_test "groups by status" test_groups_by_status
run_test "empty state" test_empty_state
run_test "dashboard from nested dirs" test_dashboard_from_nested_dirs
run_test "cards have data-item-id" test_card_has_item_id
run_test "has select toggle" test_has_select_toggle
run_test "has move-bar" test_has_move_bar

print_results
