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
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
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
