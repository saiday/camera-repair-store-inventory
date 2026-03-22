#!/usr/bin/env bash
# scripts/build.sh — Build all static output for Cloudflare Pages
#
# Usage: build.sh [data-dir] [web-dir]
# Generates: web/_data/, web/customer/, web/dashboard.html

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${1:-$SCRIPT_DIR/../data}"
WEB_DIR="${2:-$SCRIPT_DIR/../web}"

echo "=== Build: parsing items ==="
mkdir -p "$WEB_DIR/_data/items"

# Collect all items, generate items.json and per-item JSON
python3 -c "
import sys, json, os, subprocess, glob

data_dir = sys.argv[1]
web_dir = sys.argv[2]
parse_script = sys.argv[3]

repairs_dir = os.path.join(data_dir, 'repairs')
items = []
items_dir = os.path.join(web_dir, '_data', 'items')
os.makedirs(items_dir, exist_ok=True)

if os.path.isdir(repairs_dir):
    for item_md in sorted(glob.glob(os.path.join(repairs_dir, '**', 'item.md'), recursive=True)):
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)
        items.append(item)
        # Write per-item JSON (full content including description)
        with open(os.path.join(items_dir, item['id'] + '.json'), 'w') as f:
            json.dump(item, f, ensure_ascii=False, indent=2)

# Write items.json (frontmatter only — strip heavy/sensitive fields)
STRIP_FIELDS = {'description', 'cost_rows', 'page_password'}
items_light = []
for item in items:
    light = {k: v for k, v in item.items() if k not in STRIP_FIELDS}
    items_light.append(light)

with open(os.path.join(web_dir, '_data', 'items.json'), 'w') as f:
    json.dump(items_light, f, ensure_ascii=False, indent=2)

print(f'  {len(items)} items parsed')
" "$DATA_DIR" "$WEB_DIR" "$SCRIPT_DIR/parse-item.sh"

echo "=== Build: generating owners ==="
"$SCRIPT_DIR/update-owners.sh" "$DATA_DIR"
# Copy to web/_data/ for static serving
cp "$DATA_DIR/owners.json" "$WEB_DIR/_data/owners.json"

echo "=== Build: generating dashboard ==="
"$SCRIPT_DIR/generate-dashboard.sh" "$DATA_DIR" "$WEB_DIR"

echo "=== Build: generating customer pages ==="
"$SCRIPT_DIR/generate-customer-pages.sh" "$DATA_DIR" "$WEB_DIR"

echo "=== Build: generating manifest ==="
"$SCRIPT_DIR/generate-manifest.sh" "$DATA_DIR" "$WEB_DIR"

echo "=== Build complete ==="
