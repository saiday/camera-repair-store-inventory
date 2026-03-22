#!/usr/bin/env bash
# scripts/generate-manifest.sh — Generate published.json with salted password hashes
#
# Usage: generate-manifest.sh <data-dir> <web-dir>
# Generates web/_data/published.json mapping item IDs to salted hashes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="${1:?ERROR: data-dir required}"
WEB_DIR="${2:?ERROR: web-dir required}"

python3 -c "
import sys, json, os, subprocess, glob, hashlib, secrets

data_dir = sys.argv[1]
web_dir = sys.argv[2]
parse_script = sys.argv[3]

repairs_dir = os.path.join(data_dir, 'repairs')
manifest = {}

if os.path.isdir(repairs_dir):
    for item_md in sorted(glob.glob(os.path.join(repairs_dir, '**', 'item.md'), recursive=True)):
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)

        if not item.get('page_password') or item.get('status') == 'delivered':
            continue

        salt = secrets.token_hex(16)
        password_hash = hashlib.sha256((salt + item['page_password']).encode()).hexdigest()
        manifest[item['id']] = {
            'salt': salt,
            'hash': 'sha256:' + password_hash,
        }

data_dir_out = os.path.join(web_dir, '_data')
os.makedirs(data_dir_out, exist_ok=True)
with open(os.path.join(data_dir_out, 'published.json'), 'w') as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)

print(f'  {len(manifest)} published items in manifest')
" "$DATA_DIR" "$WEB_DIR" "$SCRIPT_DIR/parse-item.sh"
