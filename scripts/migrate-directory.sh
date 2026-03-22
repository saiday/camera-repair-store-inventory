#!/usr/bin/env bash
# scripts/migrate-directory.sh — Migrate flat data/repairs/ to YYYY/MM/ nesting
#
# Usage: migrate-directory.sh <data-dir>
# Moves data/repairs/{ITEM_ID}/ → data/repairs/YYYY/MM/{ITEM_ID}/
# based on received_date from each item.md frontmatter.

set -euo pipefail

[[ $# -eq 1 ]] || { echo "ERROR: Usage: migrate-directory.sh <data-dir>" >&2; exit 1; }

DATA_DIR="$1"
REPAIRS_DIR="$DATA_DIR/repairs"

[[ -d "$REPAIRS_DIR" ]] || { echo "ERROR: repairs dir not found: $REPAIRS_DIR" >&2; exit 1; }

# Find flat item directories (direct children with item.md, not already nested)
for dir in "$REPAIRS_DIR"/*/; do
  [[ -f "$dir/item.md" ]] || continue

  # Extract received_date from frontmatter
  RECEIVED_DATE="$(grep '^received_date:' "$dir/item.md" | head -1 | sed 's/^received_date: *//')"
  [[ -n "$RECEIVED_DATE" ]] || { echo "WARNING: no received_date in $dir/item.md, skipping" >&2; continue; }

  # Parse YYYY and MM
  YEAR="${RECEIVED_DATE:0:4}"
  MONTH="${RECEIVED_DATE:5:2}"

  # Skip if year looks like it's already a nested path (e.g., dir is "2026/")
  DIRNAME="$(basename "${dir%/}")"
  if [[ "$DIRNAME" =~ ^[0-9]{4}$ ]]; then
    continue
  fi

  # Create target directory and move
  TARGET="$REPAIRS_DIR/$YEAR/$MONTH/$DIRNAME"
  if [[ -d "$TARGET" ]]; then
    echo "WARNING: target already exists, skipping: $TARGET" >&2
    continue
  fi
  mkdir -p "$REPAIRS_DIR/$YEAR/$MONTH"
  mv "$dir" "$TARGET"
  echo "Moved: $DIRNAME → $YEAR/$MONTH/$DIRNAME"
done
