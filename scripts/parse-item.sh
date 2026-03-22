#!/usr/bin/env bash
# scripts/parse-item.sh — Parse and validate an item.md file, output JSON
#
# Usage: parse-item.sh <path-to-item.md>
# Output: JSON object with frontmatter fields on stdout
# Errors: prints to stderr, exits with code 1

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR: Usage: parse-item.sh <path-to-item.md>" >&2
  exit 1
fi

ITEM_FILE="$1"

if [[ ! -f "$ITEM_FILE" ]]; then
  echo "ERROR: item.md not found: $ITEM_FILE" >&2
  exit 1
fi

python3 -c "
import sys, json, os, re

item_file = sys.argv[1]
item_id = os.path.basename(os.path.dirname(item_file))

with open(item_file, 'r') as f:
    content = f.read()

fm_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not fm_match:
    print(f'ERROR: item.md parse failed — no frontmatter found in {item_id}', file=sys.stderr)
    sys.exit(1)

fields = {}
for line in fm_match.group(1).split('\n'):
    colon_idx = line.find(':')
    if colon_idx > 0:
        key = line[:colon_idx].strip()
        value = line[colon_idx+1:].strip()
        if value.startswith('\"') and value.endswith('\"'):
            value = value[1:-1]
        fields[key] = value

required = ['id','category','brand','model','serial_number','status','owner_name','owner_contact','received_date']
for field in required:
    if not fields.get(field):
        print(f\"ERROR: item.md parse failed — missing required field '{field}' in {item_id}\", file=sys.stderr)
        sys.exit(1)

valid_statuses = ['not_started','in_progress','testing','done','delivered','ice_box']
if fields['status'] not in valid_statuses:
    print(f\"ERROR: item.md parse failed — invalid status '{fields['status']}' in {item_id} (valid: {' '.join(valid_statuses)})\", file=sys.stderr)
    sys.exit(1)

valid_categories = ['camera','lens','accessory','misc']
if fields['category'] not in valid_categories:
    print(f\"ERROR: item.md parse failed — invalid category '{fields['category']}' in {item_id} (valid: {' '.join(valid_categories)})\", file=sys.stderr)
    sys.exit(1)

body = content[fm_match.end():]
if '# 維修描述' not in body:
    print(f'ERROR: item.md parse failed — missing section \"# 維修描述\" in {item_id}', file=sys.stderr)
    sys.exit(1)
if '# 費用紀錄' not in body:
    print(f'ERROR: item.md parse failed — missing section \"# 費用紀錄\" in {item_id}', file=sys.stderr)
    sys.exit(1)

result = {
    'id': fields.get('id', ''),
    'category': fields.get('category', ''),
    'brand': fields.get('brand', ''),
    'model': fields.get('model', ''),
    'serial_number': fields.get('serial_number', ''),
    'status': fields.get('status', ''),
    'owner_name': fields.get('owner_name', ''),
    'owner_contact': fields.get('owner_contact', ''),
    'received_date': fields.get('received_date', ''),
    'delivered_date': fields.get('delivered_date', ''),
}
print(json.dumps(result, ensure_ascii=False, indent=2))
" "$ITEM_FILE"
