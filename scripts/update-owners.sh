#!/usr/bin/env bash
# scripts/update-owners.sh — Rebuild owners.json from all item.md files
#
# Usage: update-owners.sh <data-dir>
# Scans all data/repairs/*/item.md, extracts owner_name + owner_contact,
# deduplicates on name+contact pair, writes to data/owners.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -eq 1 ]] || { echo "ERROR: Usage: update-owners.sh <data-dir>" >&2; exit 1; }

DATA_DIR="$1"
REPAIRS_DIR="$DATA_DIR/repairs"
OWNERS_FILE="$DATA_DIR/owners.json"

# Use Python to collect, deduplicate, and write JSON
# (bash 3.2 lacks associative arrays needed for dedup)
python3 -c "
import sys, json, os, subprocess, glob

repairs_dir = sys.argv[1]
owners_file = sys.argv[2]
parse_script = sys.argv[3]

seen = set()
owners = []

if os.path.isdir(repairs_dir):
    for item_md in sorted(glob.glob(os.path.join(repairs_dir, '**', 'item.md'), recursive=True)):
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)
        key = (item['owner_name'], item['owner_contact'])
        if key not in seen:
            seen.add(key)
            owners.append({'name': item['owner_name'], 'contact': item['owner_contact']})

with open(owners_file, 'w') as f:
    json.dump(owners, f, ensure_ascii=False, indent=2)
" "$REPAIRS_DIR" "$OWNERS_FILE" "$SCRIPT_DIR/parse-item.sh"
