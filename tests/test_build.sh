#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

test_build_generates_data_files() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  # Create a test item
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" --serial 123 \
    --owner-name "王小明" --owner-contact "0912-345-678" --description "test" --date 2026-03-22

  "$SCRIPT_DIR/build.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  assert_file_exists "$TEST_TMP/web/_data/items.json" "items.json generated"
  assert_file_exists "$TEST_TMP/web/_data/owners.json" "owners.json generated"
  assert_file_exists "$TEST_TMP/web/dashboard.html" "dashboard generated"

  # Verify items.json contains the item
  ITEMS="$(cat "$TEST_TMP/web/_data/items.json")"
  assert_contains "$ITEMS" "CAM-20260322-EOS-R5-001" "item in items.json"
  teardown
}

test_build_generates_per_item_json() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test desc" --date 2026-03-22)"

  "$SCRIPT_DIR/build.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  assert_file_exists "$TEST_TMP/web/_data/items/$ITEM_ID.json" "per-item JSON generated"
  ITEM_JSON="$(cat "$TEST_TMP/web/_data/items/$ITEM_ID.json")"
  assert_contains "$ITEM_JSON" "test desc" "per-item JSON has description"
  teardown
}

test_build_generates_customer_page_for_published() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22)"
  ITEM_DIR="$TEST_TMP/data/repairs/$ITEM_ID"
  "$SCRIPT_DIR/update-item.sh" --no-hooks --item-dir "$ITEM_DIR" --page-password "secret"

  "$SCRIPT_DIR/build.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  assert_file_exists "$TEST_TMP/web/customer/$ITEM_ID.html" "customer page generated for published item"
  CUSTOMER_PAGE="$(cat "$TEST_TMP/web/customer/$ITEM_ID.html")"
  # Should not contain owner info
  if echo "$CUSTOMER_PAGE" | grep -q "0912"; then
    echo "FAIL: customer page should not contain owner_contact"
    return 1
  fi
  teardown
}

test_build_skips_customer_page_for_unpublished() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22

  "$SCRIPT_DIR/build.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  if ls "$TEST_TMP/web/customer/"*.html 2>/dev/null | grep -q .; then
    echo "FAIL: no customer pages should be generated for unpublished items"
    return 1
  fi
  teardown
}

test_build_generates_manifest() {
  setup
  mkdir -p "$TEST_TMP/web/static"
  ITEM_ID="$("$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "test" --date 2026-03-22)"
  ITEM_DIR="$TEST_TMP/data/repairs/$ITEM_ID"
  "$SCRIPT_DIR/update-item.sh" --no-hooks --item-dir "$ITEM_DIR" --page-password "secret"

  "$SCRIPT_DIR/build.sh" "$TEST_TMP/data" "$TEST_TMP/web"

  assert_file_exists "$TEST_TMP/web/_data/published.json" "manifest generated"
  MANIFEST="$(cat "$TEST_TMP/web/_data/published.json")"
  assert_contains "$MANIFEST" "$ITEM_ID" "published item in manifest"
  assert_contains "$MANIFEST" "salt" "manifest has salt"
  assert_contains "$MANIFEST" "hash" "manifest has hash"
  teardown
}

run_test "build generates data files" test_build_generates_data_files
run_test "build generates per-item JSON" test_build_generates_per_item_json
run_test "build generates customer page for published" test_build_generates_customer_page_for_published
run_test "build skips customer page for unpublished" test_build_skips_customer_page_for_unpublished
run_test "build generates manifest" test_build_generates_manifest
print_results
