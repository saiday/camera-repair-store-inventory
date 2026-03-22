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

# --- Interactive mode: search and prompt when no args and TTY ---
if [[ $# -eq 0 && -t 0 ]]; then
  DATA_DIR="${SCRIPT_DIR}/../data"
  REPAIRS_DIR="$DATA_DIR/repairs"

  printf 'Search: ' >&2
  read -r SEARCH_QUERY

  # Direct item ID match — skip search if input is an exact directory name
  if [[ -d "$REPAIRS_DIR/$SEARCH_QUERY" && -f "$REPAIRS_DIR/$SEARCH_QUERY/item.md" ]]; then
    ITEM_DIR="$REPAIRS_DIR/$SEARCH_QUERY"
  else

  # Search items by brand, model, owner, or ID (case-insensitive)
  MATCHES=()
  MATCH_DIRS=()
  QUERY_LOWER="$(echo "$SEARCH_QUERY" | tr '[:upper:]' '[:lower:]')"
  if [[ -d "$REPAIRS_DIR" ]]; then
    for dir in "$REPAIRS_DIR"/*/; do
      [[ -f "$dir/item.md" ]] || continue
      local_json="$("$SCRIPT_DIR/parse-item.sh" "$dir/item.md" 2>/dev/null)" || continue
      IFS=$'\t' read -r local_id local_brand local_model local_owner <<< "$(echo "$local_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['id'],d['brand'],d['model'],d['owner_name'],sep='\t')")"

      # Case-insensitive match
      HAYSTACK="$(echo "$local_id $local_brand $local_model $local_owner" | tr '[:upper:]' '[:lower:]')"
      if [[ "$HAYSTACK" == *"$QUERY_LOWER"* ]]; then
        MATCHES+=("$local_id — $local_brand $local_model ($local_owner)")
        MATCH_DIRS+=("${dir%/}")
      fi
    done
  fi

  if [[ ${#MATCHES[@]} -eq 0 ]]; then
    echo "No items found matching '$SEARCH_QUERY'" >&2
    exit 1
  elif [[ ${#MATCHES[@]} -eq 1 ]]; then
    ITEM_DIR="${MATCH_DIRS[0]}"
    echo "  ${MATCHES[0]}" >&2
  else
    for i in "${!MATCHES[@]}"; do
      echo "  $((i+1))) ${MATCHES[$i]}" >&2
    done
    printf 'Select [1]: ' >&2
    read -r SELECTION
    SELECTION="${SELECTION:-1}"
    IDX=$((SELECTION - 1))
    if [[ $IDX -lt 0 || $IDX -ge ${#MATCHES[@]} ]]; then
      echo "Invalid selection" >&2
      exit 1
    fi
    ITEM_DIR="${MATCH_DIRS[$IDX]}"
  fi

  fi  # end of search branch (direct ID match skips here)

  # Parse current item for display
  CURRENT_JSON="$("$SCRIPT_DIR/parse-item.sh" "$ITEM_DIR/item.md")"
  IFS=$'\t' read -r CURRENT_STATUS CURRENT_BRAND CURRENT_MODEL CURRENT_OWNER <<< "$(echo "$CURRENT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'],d['brand'],d['model'],d['owner_name'],sep='\t')")"

  echo "" >&2
  echo "Current: status=$CURRENT_STATUS, brand=$CURRENT_BRAND, model=$CURRENT_MODEL, owner=$CURRENT_OWNER" >&2
  printf 'New status (not_started/in_progress/testing/done/delivered/ice_box) [%s]: ' "$CURRENT_STATUS" >&2
  read -r STATUS
  STATUS="${STATUS:-}"

  printf 'Add cost? (y/N): ' >&2
  read -r ADD_COST
  COST_AMOUNT="" COST_NOTE="" COST_DATE=""
  if [[ "$ADD_COST" =~ ^[Yy]$ ]]; then
    printf '  Amount: ' >&2
    read -r COST_AMOUNT
    printf '  Note: ' >&2
    read -r COST_NOTE
    if [[ -n "$COST_AMOUNT" && -n "$COST_NOTE" ]]; then
      COST_DATE="$(date +%Y-%m-%d)"
    fi
  fi

  # Set remaining vars to empty (not updating)
  OWNER_NAME="" OWNER_CONTACT="" DESCRIPTION="" BRAND="" SERIAL=""
  DELIVERED_DATE="" NO_HOOKS=""

  # If status is delivered, auto-set delivered_date
  if [[ "$STATUS" == "delivered" ]]; then
    DELIVERED_DATE="$(date +%Y-%m-%d)"
  fi

  ITEM_FILE="$ITEM_DIR/item.md"
  # Skip to the Python update section
else
  # --- Parse arguments ---
  ITEM_DIR="" STATUS="" OWNER_NAME="" OWNER_CONTACT="" DESCRIPTION="" BRAND="" SERIAL=""
  COST_AMOUNT="" COST_NOTE="" COST_DATE="" DELIVERED_DATE="" NO_HOOKS=""

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
      --no-hooks) NO_HOOKS="1"; shift ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  [[ -n "$ITEM_DIR" ]] || { echo "ERROR: --item-dir is required" >&2; exit 1; }

  # Default cost date to today only when a cost entry is being added
  if [[ -n "$COST_AMOUNT" && -n "$COST_NOTE" && -z "$COST_DATE" ]]; then
    COST_DATE="$(date +%Y-%m-%d)"
  fi

  ITEM_FILE="$ITEM_DIR/item.md"
  [[ -f "$ITEM_FILE" ]] || { echo "ERROR: item.md not found in $ITEM_DIR" >&2; exit 1; }
fi

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

# --- Success message for interactive mode ---
if [[ -t 0 && -t 1 ]]; then
  ITEM_ID="$(basename "$ITEM_DIR")"
  echo "✓ Updated $ITEM_ID" >&2
fi

# --- Run hooks (unless --no-hooks) ---
if [[ -z "$NO_HOOKS" ]]; then
  # Derive data-dir from item-dir (two levels up: repairs/<id>/item.md → data/)
  HOOKS_DATA_DIR="$(cd "$ITEM_DIR/../.." && pwd)"
  "$SCRIPT_DIR/update-owners.sh" "$HOOKS_DATA_DIR" &
  "$SCRIPT_DIR/generate-dashboard.sh" "$HOOKS_DATA_DIR" &
fi
