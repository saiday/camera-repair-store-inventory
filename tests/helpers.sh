#!/usr/bin/env bash
# tests/helpers.sh — shared test utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
TEST_TMP=""

setup() {
  TEST_TMP="$(mktemp -d)"
  mkdir -p "$TEST_TMP/data/repairs"
  echo '[]' > "$TEST_TMP/data/owners.json"
}

teardown() {
  [[ -n "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${msg:-assert_eq}"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    return 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL: ${msg:-assert_contains}"
    echo "  expected to contain: $needle"
    echo "  actual: $haystack"
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: ${msg:-assert_file_exists} — file not found: $path"
    return 1
  fi
}

assert_dir_exists() {
  local path="$1" msg="${2:-}"
  if [[ ! -d "$path" ]]; then
    echo "FAIL: ${msg:-assert_dir_exists} — directory not found: $path"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-}"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: ${msg:-assert_exit_code}"
    echo "  expected exit code: $expected"
    echo "  actual exit code:   $actual"
    return 1
  fi
}

pass() {
  echo "PASS: $1"
}

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

print_results() {
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  [[ "$FAIL_COUNT" -eq 0 ]] || exit 1
}
