#!/usr/bin/env bash
# scripts/update-item.sh — Update an existing item's item.md
#
# Usage: update-item.sh --item-dir <dir> [--status <s>] [--owner-name <n>]
#        [--owner-contact <c>] [--description <d>] [--brand <b>] [--serial <s>]
#        [--cost-amount <a> --cost-note <n> --cost-date <d>]
#        [--delivered-date <d>]
#
# Only specified fields are updated; others remain unchanged.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse arguments ---
ITEM_DIR="" STATUS="" OWNER_NAME="" OWNER_CONTACT="" DESCRIPTION="" BRAND="" SERIAL=""
COST_AMOUNT="" COST_NOTE="" COST_DATE="" DELIVERED_DATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --item-dir) ITEM_DIR="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --owner-name) OWNER_NAME="$2"; shift 2 ;;
    --owner-contact) OWNER_CONTACT="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --brand) BRAND="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    --cost-amount) COST_AMOUNT="$2"; shift 2 ;;
    --cost-note) COST_NOTE="$2"; shift 2 ;;
    --cost-date) COST_DATE="$2"; shift 2 ;;
    --delivered-date) DELIVERED_DATE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$ITEM_DIR" ]] || { echo "ERROR: --item-dir is required" >&2; exit 1; }

# Default cost date to today if not provided
[[ -z "$COST_DATE" ]] && COST_DATE="$(date +%Y-%m-%d)"

ITEM_FILE="$ITEM_DIR/item.md"
[[ -f "$ITEM_FILE" ]] || { echo "ERROR: item.md not found in $ITEM_DIR" >&2; exit 1; }

# --- Apply field updates via Python ---
# All user values passed as sys.argv to prevent shell injection
python3 -c '
import sys, re

item_file      = sys.argv[1]
status_val     = sys.argv[2]
owner_name     = sys.argv[3]
owner_contact  = sys.argv[4]
brand_val      = sys.argv[5]
serial_val     = sys.argv[6]
delivered_val  = sys.argv[7]
description_val = sys.argv[8]
cost_amount    = sys.argv[9]
cost_note      = sys.argv[10]
cost_date      = sys.argv[11]

with open(item_file, "r") as f:
    content = f.read()

# Parse out frontmatter boundaries
fm_match = re.match(r"^(---\n)(.*?)(\n---)", content, re.DOTALL)
if not fm_match:
    print("ERROR: no frontmatter found", file=sys.stderr)
    sys.exit(1)

pre    = fm_match.group(1)
fm     = fm_match.group(2)
post   = fm_match.group(3)
rest   = content[fm_match.end():]

def replace_field(fm_text, field, new_value):
    lines = fm_text.split("\n")
    result = []
    for line in lines:
        if re.match(r"^" + re.escape(field) + r":", line):
            result.append(field + ": " + new_value)
        else:
            result.append(line)
    return "\n".join(result)

if status_val:
    fm = replace_field(fm, "status", status_val)
if owner_name:
    fm = replace_field(fm, "owner_name", owner_name)
if owner_contact:
    fm = replace_field(fm, "owner_contact", owner_contact)
if brand_val:
    fm = replace_field(fm, "brand", brand_val)
if serial_val:
    fm = replace_field(fm, "serial_number", "\"" + serial_val + "\"")
if delivered_val:
    fm = replace_field(fm, "delivered_date", delivered_val)

if description_val:
    def desc_replacer(m):
        return m.group(1) + "\n" + description_val + "\n" + m.group(2)
    rest = re.sub(
        r"(# 維修描述\n).*?(\n# 費用紀錄)",
        desc_replacer,
        rest,
        flags=re.DOTALL
    )

if cost_amount and cost_note:
    cost_line = "| " + cost_date + " | " + cost_amount + " | " + cost_note + " |"
    rest = rest.rstrip("\n") + "\n" + cost_line + "\n"

new_content = pre + fm + post + rest
with open(item_file, "w") as f:
    f.write(new_content)
' "$ITEM_FILE" "$STATUS" "$OWNER_NAME" "$OWNER_CONTACT" "$BRAND" "$SERIAL" "$DELIVERED_DATE" "$DESCRIPTION" "$COST_AMOUNT" "$COST_NOTE" "$COST_DATE"

# --- Validate ---
"$SCRIPT_DIR/parse-item.sh" "$ITEM_FILE" > /dev/null
