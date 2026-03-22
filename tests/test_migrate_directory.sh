#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

test_migrate_moves_items_to_nested_dirs() {
  setup
  # Create a flat item
  mkdir -p "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001/logs"
  cat > "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345"
status: not_started
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

test

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
ITEM

  "$SCRIPT_DIR/migrate-directory.sh" "$TEST_TMP/data"

  assert_file_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/item.md" "item moved to nested dir"
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/logs" "logs dir moved too"
  # Old flat dir should not exist
  if [[ -d "$TEST_TMP/data/repairs/CAM-20260322-EOS-R5-001" ]]; then
    echo "FAIL: old flat directory still exists"
    return 1
  fi
  teardown
}

test_migrate_skips_already_nested() {
  setup
  mkdir -p "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001"
  cat > "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/item.md" << 'ITEM'
---
id: CAM-20260322-EOS-R5-001
category: camera
brand: Canon
model: EOS R5
serial_number: "012345"
status: not_started
owner_name: 王小明
owner_contact: 0912-345-678
received_date: 2026-03-22
delivered_date:
---

# 維修描述

test

# 費用紀錄

| 日期 | 金額 | 說明 |
|------|------|------|
ITEM

  # Should not fail on already-nested items
  "$SCRIPT_DIR/migrate-directory.sh" "$TEST_TMP/data"
  assert_file_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001/item.md" "nested item still exists"
  teardown
}

test_migrate_empty_repairs() {
  setup
  "$SCRIPT_DIR/migrate-directory.sh" "$TEST_TMP/data"
  # Should succeed with no items
  assert_exit_code 0 $? "empty repairs dir"
  teardown
}

run_test "migrate moves items to nested dirs" test_migrate_moves_items_to_nested_dirs
run_test "migrate skips already nested" test_migrate_skips_already_nested
run_test "migrate empty repairs" test_migrate_empty_repairs
print_results
