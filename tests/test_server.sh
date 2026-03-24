#!/usr/bin/env bash
# tests/test_server.sh — Integration tests for the HTTP server

set -euo pipefail
source "$(dirname "$0")/helpers.sh"

SERVER_PID=""

trap 'stop_server; teardown' EXIT

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
  assert_dir_exists "$TEST_TMP/data/repairs/2026/03/CAM-20260322-EOS-R5-001" "item dir should exist"
  stop_server
  teardown
}

# --- Test: GET /api/items returns item list ---
test_get_items() {
  setup
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
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
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
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
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
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

test_api_items_nested_dirs() {
  setup
  start_server
  # Create an item (now nested)
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model Test --serial 123 \
    --owner-name Test --owner-contact 0912 --description "nested" --date 2026-03-22
  RESPONSE="$(curl -s "http://localhost:$TEST_PORT/api/items")"
  assert_contains "$RESPONSE" "CAM-20260322-Test-001" "item found via API from nested dir"
  stop_server
  teardown
}

# --- Test: POST /api/update changes item status ---
test_update_status() {
  setup
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  start_server
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/update" \
    -H "Content-Type: application/json" \
    -d '{"id": "CAM-20260322-EOS-R5-001", "status": "in_progress"}')"
  assert_contains "$response" '"ok"' "update should return ok"

  # Verify the item status changed
  local raw
  raw="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$raw" "status: in_progress" "item status should be updated"
  stop_server
  teardown
}

# --- Test: POST /api/batch-update changes multiple item statuses ---
test_batch_update() {
  setup
  # Create two items
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "王小明" --owner-contact "0912" \
    --description "Test1" --date "2026-03-22" > /dev/null
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category lens --brand Canon --model "RF50" \
    --serial "002" --owner-name "王小明" --owner-contact "0912" \
    --description "Test2" --date "2026-03-22" > /dev/null
  start_server

  # Batch update both items
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": [
      {"id": "CAM-20260322-EOS-R5-001", "status": "in_progress"},
      {"id": "LENS-20260322-RF50-001", "status": "done"}
    ]}')"
  assert_contains "$response" '"ok"' "batch-update should return ok"
  assert_contains "$response" "CAM-20260322-EOS-R5-001" "response should list first item"
  assert_contains "$response" "LENS-20260322-RF50-001" "response should list second item"

  # Verify both items changed
  local raw1 raw2
  raw1="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$raw1" "status: in_progress" "first item status should be updated"
  raw2="$(curl -s "http://localhost:$TEST_PORT/api/item/LENS-20260322-RF50-001/raw")"
  assert_contains "$raw2" "status: done" "second item status should be updated"

  stop_server
  teardown
}

# --- Test: POST /api/batch-update validates input ---
test_batch_update_validation() {
  setup
  start_server

  # Empty updates array
  local response
  response="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": []}')"
  assert_eq "400" "$response" "empty updates should return 400"

  # Duplicate IDs
  response="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": [{"id": "X-001", "status": "done"}, {"id": "X-001", "status": "done"}]}')"
  assert_eq "400" "$response" "duplicate IDs should return 400"

  stop_server
  teardown
}

# --- Test: POST /api/batch-update partial failure ---
test_batch_update_partial_failure() {
  setup
  "$SCRIPT_DIR/create-item.sh" --no-hooks --data-dir "$TEST_TMP/data" \
    --category camera --brand Canon --model "EOS R5" \
    --serial "001" --owner-name "Test" --owner-contact "0912" \
    --description "Test" --date "2026-03-22" > /dev/null
  start_server

  # One valid ID, one non-existent
  local response
  response="$(curl -s -X POST "http://localhost:$TEST_PORT/api/batch-update" \
    -H "Content-Type: application/json" \
    -d '{"updates": [
      {"id": "CAM-20260322-EOS-R5-001", "status": "in_progress"},
      {"id": "NONEXISTENT-20260101-X-001", "status": "done"}
    ]}')"
  assert_contains "$response" '"succeeded"' "should report succeeded list"
  assert_contains "$response" '"failed"' "should report failed list"
  assert_contains "$response" "CAM-20260322-EOS-R5-001" "succeeded should contain valid item"

  # Verify the valid item was still updated
  local raw
  raw="$(curl -s "http://localhost:$TEST_PORT/api/item/CAM-20260322-EOS-R5-001/raw")"
  assert_contains "$raw" "status: in_progress" "valid item should still be updated"

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
run_test "GET /api/items nested dirs" test_api_items_nested_dirs
run_test "POST /api/update status" test_update_status
run_test "POST /api/batch-update" test_batch_update
run_test "POST /api/batch-update validation" test_batch_update_validation
run_test "POST /api/batch-update partial failure" test_batch_update_partial_failure

print_results
