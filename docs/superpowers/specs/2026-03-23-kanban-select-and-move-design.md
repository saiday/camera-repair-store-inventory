# Kanban Select & Move — Design Spec

## Overview

Add a selection mode to the kanban dashboard so users can select one or more repair item cards and move them to a different status column without leaving the board. Optimized for phone/tablet — the primary device for this workflow.

## Problem

Changing an item's status currently requires: tap card → navigate to entry page → change dropdown → submit form → wait for redirect back. This is high-friction for a several-times-a-day action that only changes one field.

## User Flow

1. User taps **"選取"** button in the toolbar (appended after existing nav links).
2. Board enters **selection mode**:
   - Cards suppress navigation (`e.preventDefault()` on click) — tapping toggles selection instead.
   - Selected cards get a blue highlight and checkmark badge.
   - A **"移動到"** action bar appears fixed at the bottom of the viewport.
   - The bar shows: selected count ("已選 N 件"), status pills, and a "取消" cancel button.
3. User taps cards to select/deselect. Multiple cards across different columns and the ice box section can be selected.
4. User taps a status pill in the action bar. Pills are disabled (grayed out) when selection count is 0.
5. A **confirmation dialog** appears: "確定移動 N 件到 {display label}？" (uses browser `confirm()`).
6. On confirm: each selected item's status is updated via the existing `/api/update` endpoint. All calls complete before the page reloads.
7. On cancel/取消: selection is cleared, board returns to normal mode.

## Status Mapping

The action bar pills display Traditional Chinese labels but send internal API keys:

| Display Label | API Value |
|---------------|-----------|
| 未開始 | `not_started` |
| 進行中 | `in_progress` |
| 測試中 | `testing` |
| 完成・待取件 | `done` |
| 冰箱 | `ice_box` |

`delivered` (已交付) is excluded — delivered items don't appear on the board, and marking as delivered is a distinct workflow handled on the entry page.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Enter selection mode | Explicit "選取" toggle button in `.toolbar` | Discoverable, no hidden gestures — important for mobile-first |
| Status pills in action bar | Always show all statuses | Simpler logic; moving to the same status is harmless (no-op) |
| Zero selection guard | Pills disabled when count is 0 | Prevents pointless confirmation dialogs |
| Post-move feedback | `confirm()` dialog before moving | Prevents accidental moves on a high-frequency touch workflow |
| Batch support | Yes, multi-select | Natural extension of the select pattern; common to need to move multiple items at once |
| Navigation in selection mode | `e.preventDefault()` on card `<a>` clicks | Clear mode separation — normal mode taps navigate, selection mode taps select |
| Ice box cards | Selectable in selection mode | Same cards, same behavior; collapsing the ice box in selection mode deselects any ice box cards and updates the count |

## Architecture

### No server changes

The existing `/api/update` endpoint accepts a status field and handles the full update cycle (write to `item.md`, run hooks to regenerate dashboard and owners). No new endpoints needed.

### Client-side changes

**`generate-dashboard.sh`** — add to generated HTML:
- A "選取" toggle button appended to the existing `<nav class="toolbar">`.
- A hidden action bar (`div.move-bar`) at the bottom of the page, shown only in selection mode.
- Each `<a class="card">` gets a `data-item-id` attribute set to the item's ID (same value already rendered in `.card-id`).

**`web/static/dashboard.js`** — new logic:
- Selection mode state management (enter/exit).
- Click handler on all `.card` elements: in selection mode, call `e.preventDefault()` and toggle `.selected` class + checkmark.
- Action bar count update on every toggle.
- Status pill click → `confirm()` dialog → sequential `fetch()` calls to `/api/update` for each selected item → `location.reload()` after all complete.
- Each `fetch()` sends: `{ "id": itemId, "status": apiValue }` (only `id` and `status` — the server handles partial updates).

### CSS additions in `web/static/style.css`

- `.card.selected` — blue border (`#4a90d9`) + light blue background (`#e8f4fd`).
- `.card.selected::after` — checkmark badge positioned top-right.
- `.move-bar` — `position: fixed; bottom: 0`, hidden by default, shown in selection mode.
- `.move-bar .status-pill` — colored pill buttons for each status, with a `.disabled` state for zero selection.
- `.select-toggle` — button styling in toolbar.

## Edge Cases

- **Partial batch failure**: if a `fetch()` call fails mid-batch, abort remaining calls and show an alert with how many succeeded and how many failed. Don't clear selection — the user can deselect the moved items (which will be gone after reload anyway) and retry. Reload the page so successfully moved items reflect their new status.
- **Mixed statuses selected**: all selected items move to the chosen status regardless of their current status.
- **Ice box collapsed during selection**: collapsing the ice box deselects any selected ice box cards and updates the count in the action bar.
- **No items on board**: "選取" button still visible but enters an empty selection mode — harmless.

## Scope

**In scope:**
- Selection mode toggle
- Multi-select cards (columns + ice box)
- Action bar with status pills
- Confirmation dialog
- Batch status update via existing API
- Mobile-optimized touch targets

**Out of scope:**
- Drag and drop
- Reordering within columns
- Quick-editing other fields from the board
- Undo after move
