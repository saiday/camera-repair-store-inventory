#!/usr/bin/env bash
# tests/test_parse_item.sh

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

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
  exit_code=0
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
  exit_code=0
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
  exit_code=0
  output="$("$SCRIPT_DIR/parse-item.sh" "$item_dir/item.md" 2>&1)" || exit_code=$?
  assert_eq "1" "$exit_code" "should fail for missing cost section"
  assert_contains "$output" "費用紀錄" "error should mention missing section"
  teardown
}

# --- Test: file not found ---
test_file_not_found() {
  setup
  local output exit_code
  exit_code=0
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

print_results
