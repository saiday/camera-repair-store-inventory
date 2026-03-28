#!/usr/bin/env bash
# scripts/create-item.sh — Create a new repair item
#
# Usage: create-item.sh --data-dir <dir> --category <cat> --brand <brand>
#        --model <model> --serial <sn> --owner-name <name> --owner-contact <contact>
#        --description <desc> --date <YYYY-MM-DD>
#        [--cost-amount <amount> --cost-note <note>]
#
# Output: the created item ID on stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helper: prompt until non-empty ---
prompt_required() {
  local prompt_text="$1" value=""
  while true; do
    printf '%s' "$prompt_text" >&2
    read -r value
    if [[ -n "$value" ]]; then
      echo "$value"
      return
    fi
    echo "This field is required." >&2
  done
}

# --- Interactive mode: prompt for each field when no args and TTY ---
if [[ $# -eq 0 && -t 0 ]]; then
  DATA_DIR="${SCRIPT_DIR}/../data"

  # Category (validated against enum)
  while true; do
    printf 'Category (camera/lens/accessory/misc): ' >&2
    read -r CATEGORY
    case "$CATEGORY" in
      camera|lens|accessory|misc) break ;;
      *) echo "Invalid category. Choose: camera, lens, accessory, misc" >&2 ;;
    esac
  done

  BRAND="$(prompt_required 'Brand: ')"
  MODEL="$(prompt_required 'Model: ')"
  SERIAL="$(prompt_required 'Serial: ')"
  OWNER_NAME="$(prompt_required 'Owner: ')"
  OWNER_CONTACT="$(prompt_required 'Contact: ')"
  DESCRIPTION="$(prompt_required 'Description: ')"

  TODAY="$(date +%Y-%m-%d)"
  printf 'Date [%s]: ' "$TODAY" >&2
  read -r DATE
  DATE="${DATE:-$TODAY}"

  # Fall through to the rest of the script with variables set
  NO_HOOKS=""
  COST_AMOUNT=""
  COST_NOTE=""
else
# --- Parse arguments ---
DATA_DIR="" CATEGORY="" BRAND="" MODEL="" SERIAL="" OWNER_NAME="" OWNER_CONTACT=""
DESCRIPTION="" DATE="" COST_AMOUNT="" COST_NOTE="" NO_HOOKS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --category) CATEGORY="$2"; shift 2 ;;
    --brand) BRAND="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --serial) SERIAL="$2"; shift 2 ;;
    --owner-name) OWNER_NAME="$2"; shift 2 ;;
    --owner-contact) OWNER_CONTACT="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    --cost-amount) COST_AMOUNT="$2"; shift 2 ;;
    --cost-note) COST_NOTE="$2"; shift 2 ;;
    --no-hooks) NO_HOOKS="1"; shift ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Validate required args ---
# (bash 3.2 compatible — no ${!var} indirect expansion)
for pair in "DATA_DIR:$DATA_DIR" "CATEGORY:$CATEGORY" "BRAND:$BRAND" "MODEL:$MODEL" \
            "SERIAL:$SERIAL" "OWNER_NAME:$OWNER_NAME" "OWNER_CONTACT:$OWNER_CONTACT" \
            "DESCRIPTION:$DESCRIPTION" "DATE:$DATE"; do
  var_name="${pair%%:*}"
  var_val="${pair#*:}"
  if [[ -z "$var_val" ]]; then
    echo "ERROR: Missing required argument --$(echo "$var_name" | tr '_' '-' | tr '[:upper:]' '[:lower:]')" >&2
    exit 1
  fi
done
fi

# --- Map category to type prefix ---
case "$CATEGORY" in
  camera) TYPE_PREFIX="CAM" ;;
  lens) TYPE_PREFIX="LENS" ;;
  accessory) TYPE_PREFIX="ACCE" ;;
  misc) TYPE_PREFIX="OTH" ;;
  *) echo "ERROR: Invalid category '$CATEGORY'" >&2; exit 1 ;;
esac

# --- Normalize model name for ID ---
# Spaces become dashes, remove non-alphanumeric except dashes, preserve case
NORMALIZED_MODEL="$(echo "$MODEL" | sed 's/ /-/g' | sed 's/[^A-Za-z0-9-]//g')"

# --- Format date components ---
DATE_COMPACT="${DATE//-/}"

# --- Determine sequence number ---
PREFIX="${TYPE_PREFIX}-${DATE_COMPACT}-${NORMALIZED_MODEL}"
SEQ=1
REPAIRS_DIR="$DATA_DIR/repairs"
while [[ -d "$REPAIRS_DIR/${PREFIX}-$(printf '%03d' $SEQ)" ]]; do
  SEQ=$((SEQ + 1))
done
SEQ_PADDED="$(printf '%03d' $SEQ)"

ITEM_ID="${PREFIX}-${SEQ_PADDED}"
ITEM_DIR="$REPAIRS_DIR/$ITEM_ID"

# --- Create directory structure ---
mkdir -p "$ITEM_DIR/logs"

# --- Build cost table content ---
COST_ROWS=""
if [[ -n "$COST_AMOUNT" && -n "$COST_NOTE" ]]; then
  COST_ROWS="| $DATE | $COST_AMOUNT | $COST_NOTE |"
fi

# --- Write item.md ---
# Use printf to avoid shell interpolation of user input (heredoc with unquoted
# delimiter would expand $, `, etc. in description/owner fields).
{
  printf '%s\n' "---"
  printf '%s\n' "id: $ITEM_ID"
  printf '%s\n' "category: $CATEGORY"
  printf '%s\n' "brand: $BRAND"
  printf '%s\n' "model: $MODEL"
  printf '%s\n' "serial_number: \"$SERIAL\""
  printf '%s\n' "status: not_started"
  printf '%s\n' "owner_name: $OWNER_NAME"
  printf '%s\n' "owner_contact: $OWNER_CONTACT"
  printf '%s\n' "received_date: $DATE"
  printf '%s\n' "delivered_date:"
  printf '%s\n' "page_password:"
  printf '%s\n' "---"
  printf '\n'
  printf '%s\n' "# 維修描述"
  printf '\n'
  printf '%s\n' "$DESCRIPTION"
  printf '\n'
  printf '%s\n' "# 費用紀錄"
  printf '\n'
  printf '%s\n' "| 日期 | 金額 | 說明 |"
  printf '%s\n' "|------|------|------|"
  [[ -n "$COST_ROWS" ]] && printf '%s\n' "$COST_ROWS"
} > "$ITEM_DIR/item.md"

# --- Validate the created file ---
"$SCRIPT_DIR/parse-item.sh" "$ITEM_DIR/item.md" > /dev/null

# --- Output the item ID ---
if [[ -t 1 ]]; then
  echo "✓ Created $ITEM_ID" >&2
fi
echo "$ITEM_ID"

# --- Run hooks (unless --no-hooks) ---
if [[ -z "$NO_HOOKS" ]]; then
  "$SCRIPT_DIR/update-owners.sh" "$DATA_DIR" &
  # generate-dashboard.sh defaults web-dir to $SCRIPT_DIR/../web when not passed
  "$SCRIPT_DIR/generate-dashboard.sh" "$DATA_DIR" &
fi
