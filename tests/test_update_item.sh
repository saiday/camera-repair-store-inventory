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
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
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
