# Camera Repair Shop Inventory System

## Tech Constraints

- **Bash 3.2** — macOS default. No `declare -A`, no `local -n`, no `${!var}`. Use inline Python when you need associative data structures.
- **Python 3 stdlib only** — no pip, no venv, no third-party packages.
- **Vanilla HTML/CSS/JS** — no build step, no framework.

## Non-Obvious Design Decisions

- **Hooks are called by server.py, not by shell scripts.** After create/update API calls, `server.py._run_hooks()` calls `update-owners.sh` and `generate-dashboard.sh`. Shell scripts themselves do NOT call hooks. New scripts that mutate data should follow this same pattern.
- **UI text is Traditional Chinese; script output and error messages are English.**
