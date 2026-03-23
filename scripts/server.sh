#!/usr/bin/env bash
# scripts/server.sh — One-command start for the inventory server
#
# Usage: ./scripts/server.sh
# Checks for Python 3, kills any existing process on port 8787, starts the server.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT=8787

# --- Check Python 3 ---
if ! command -v python3 &>/dev/null; then
  echo "ERROR: Python 3 is required but not found." >&2
  echo "macOS should have it pre-installed. Try: xcode-select --install" >&2
  exit 1
fi

# --- Kill existing process on port ---
existing_pids="$(lsof -ti :$PORT 2>/dev/null || true)"
if [[ -n "$existing_pids" ]]; then
  echo "Killing existing process(es) on port $PORT (PIDs: $(echo $existing_pids))"
  echo "$existing_pids" | xargs kill 2>/dev/null || true
  sleep 1
fi

# --- Ensure data directories exist ---
mkdir -p "$PROJECT_DIR/data/repairs"
[[ -f "$PROJECT_DIR/data/owners.json" ]] || echo '[]' > "$PROJECT_DIR/data/owners.json"

# --- Generate initial dashboard if missing ---
if [[ ! -f "$PROJECT_DIR/web/dashboard.html" ]]; then
  echo "Generating initial dashboard..."
  "$SCRIPT_DIR/generate-dashboard.sh" "$PROJECT_DIR/data" "$PROJECT_DIR/web"
fi

# --- Start server ---
echo "Starting server on http://localhost:$PORT"
python3 "$SCRIPT_DIR/server.py" \
  --port "$PORT" \
  --data-dir "$PROJECT_DIR/data" \
  --web-dir "$PROJECT_DIR/web" \
  --scripts-dir "$SCRIPT_DIR"
