#!/usr/bin/env bash
# tests/test_update_item.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"


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
page_password:
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
    --no-hooks \
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
    --no-hooks \
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
    --no-hooks \
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
    --no-hooks \
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
    --no-hooks \
    --item-dir "$item_dir" \
    --description "觀景窗有霧氣，快門異音，需拆機檢查"

  local content
  content="$(cat "$item_dir/item.md")"
  assert_contains "$content" "觀景窗有霧氣，快門異音，需拆機檢查" "description should be updated"
  teardown
}

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

test_update_page_password() {
  setup
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22)"
  ITEM_DIR="$TEST_TMP/data/repairs/$ITEM_ID"

  "$SCRIPT_DIR/update-item.sh" --no-hooks --item-dir "$ITEM_DIR" --page-password "secret123"

  CONTENT="$(cat "$ITEM_DIR/item.md")"
  assert_contains "$CONTENT" "page_password: secret123" "page_password set"
  teardown
}

test_update_delivered_clears_page_password() {
  setup
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22)"
  ITEM_DIR="$TEST_TMP/data/repairs/$ITEM_ID"

  # First set a page_password
  "$SCRIPT_DIR/update-item.sh" --no-hooks --item-dir "$ITEM_DIR" --page-password "secret123"
  # Then deliver
  "$SCRIPT_DIR/update-item.sh" --no-hooks --item-dir "$ITEM_DIR" --status delivered --delivered-date 2026-03-25

  CONTENT="$(cat "$ITEM_DIR/item.md")"
  assert_contains "$CONTENT" "page_password:" "page_password cleared on delivered"
  # Ensure it's empty (just "page_password:" with nothing after)
  if echo "$CONTENT" | grep -q "page_password: ."; then
    echo "FAIL: page_password should be empty after delivery"
    return 1
  fi
  teardown
}

# --- Run all tests ---
echo "=== update-item.sh tests ==="
run_test "update status" test_update_status
run_test "update owner" test_update_owner
run_test "add cost entry" test_add_cost
run_test "delivered sets date" test_delivered_sets_date
run_test "update description" test_update_description
run_test "--no-hooks flag" test_no_hooks_flag
run_test "update page_password" test_update_page_password
run_test "delivered clears page_password" test_update_delivered_clears_page_password

print_results
