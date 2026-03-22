#!/usr/bin/env bash
# tests/test_create_item.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"


# --- Test: create a basic item ---
test_create_basic() {
  setup
  local output
  output="$("$SCRIPT_DIR/create-item.sh" \
    --no-hooks \
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
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001" "item dir should exist"

  # item.md should exist and be parseable
  assert_file_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/item.md" "item.md should exist"

  # logs/ should exist
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/logs" "logs dir should exist"

  # Verify parseable
  "$SCRIPT_DIR/parse-item.sh" "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/item.md" > /dev/null

  teardown
}

# --- Test: model name normalization ---
test_model_normalization() {
  setup
  local output
  output="$("$SCRIPT_DIR/create-item.sh" \
    --no-hooks \
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
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/LENS-20260322-SEL-24-70-GM-001" "normalized dir should exist"
  teardown
}

# --- Test: sequence number increments ---
test_sequence_increment() {
  setup
  # Create first item
  "$SCRIPT_DIR/create-item.sh" \
    --no-hooks \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "A" --owner-contact "a" \
    --description "First" --date "2026-03-22" > /dev/null

  # Create second item with same type/date/model
  local output
  output="$("$SCRIPT_DIR/create-item.sh" \
    --no-hooks \
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
    --no-hooks \
    --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "A" --owner-contact "a" \
    --description "Test" --date "2026-03-22" \
    --cost-amount "3000" --cost-note "初步估價" > /dev/null

  local content
  content="$(cat "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/item.md")"
  assert_contains "$content" "| 2026-03-22 | 3000 | 初步估價 |" "should contain cost entry"
  teardown
}

# --- Test: category prefix mapping ---
test_category_prefixes() {
  setup
  local output

  output="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category accessory --brand Peak --model "Slide Lite" \
    --serial "A1" --owner-name "A" --owner-contact "a" \
    --description "T" --date "2026-03-22")"
  assert_contains "$output" "ACCE-" "accessory should use ACCE prefix"

  output="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category misc --brand Other --model "Widget" \
    --serial "M1" --owner-name "A" --owner-contact "a" \
    --description "T" --date "2026-03-22")"
  assert_contains "$output" "OTH-" "misc should use OTH prefix"

  teardown
}

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
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001" "item should exist"

  # owners.json should still be empty (hooks were skipped)
  local owners
  owners="$(cat "$TEST_TMP/data/owners.json")"
  assert_eq "[]" "$owners" "owners.json should remain empty when --no-hooks"

  teardown
}

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

# --- Run all tests ---
echo "=== create-item.sh tests ==="
run_test "create basic item" test_create_basic
run_test "model normalization" test_model_normalization
run_test "sequence increment" test_sequence_increment
run_test "initial cost entry" test_initial_cost
run_test "category prefixes" test_category_prefixes
run_test "--no-hooks flag" test_no_hooks_flag
run_test "hooks run by default" test_hooks_run_by_default

test_create_nested_directory() {
  setup
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22)"
  assert_file_exists "$TEST_TMP/data/repairs/2026/03/$ITEM_ID/item.md" "item in nested dir"
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/$ITEM_ID/logs" "logs in nested dir"
  teardown
}

test_create_includes_page_password() {
  setup
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22)"
  CONTENT="$(cat "$TEST_TMP/data/repairs/2026/03/$ITEM_ID/item.md")"
  assert_contains "$CONTENT" "page_password:" "page_password field exists in frontmatter"
  teardown
}

test_create_sequence_in_nested_dir() {
  setup
  ID1="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" --serial 111 \
    --owner-name A --owner-contact 111 --description "first" --date 2026-03-22)"
  ID2="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" --serial 222 \
    --owner-name B --owner-contact 222 --description "second" --date 2026-03-22)"
  assert_contains "$ID1" "001" "first item is 001"
  assert_contains "$ID2" "002" "second item is 002"
  teardown
}

run_test "create nested directory" test_create_nested_directory
run_test "create includes page_password" test_create_includes_page_password
run_test "create sequence in nested dir" test_create_sequence_in_nested_dir

print_results
