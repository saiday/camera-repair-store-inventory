#!/usr/bin/env bash
# tests/test_update_owners.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"


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

test_owners_from_nested_dirs() {
  setup
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name "王小明" --owner-contact "0912-345-678" --description "test" --date 2026-03-22
  "$SCRIPT_DIR/update-owners.sh" "$TEST_TMP/data"
  OWNERS="$(cat "$TEST_TMP/data/owners.json")"
  assert_contains "$OWNERS" "王小明" "owner found from nested dir"
  teardown
}

# --- Run all tests ---
echo "=== update-owners.sh tests ==="
run_test "builds owners from items" test_builds_owners
run_test "deduplicates on name+contact" test_dedup
run_test "same name different contact" test_same_name_different_contact
run_test "owners from nested dirs" test_owners_from_nested_dirs

print_results
