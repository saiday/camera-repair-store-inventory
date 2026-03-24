# Camera Repair Shop Inventory System

## Tech Constraints

- **Bash 3.2** — macOS default. No `declare -A`, no `local -n`, no `${!var}`. Use inline Python when you need associative data structures.
- **Python 3 stdlib only** — no pip, no venv, no third-party packages.
- **Vanilla HTML/CSS/JS** — no build step, no framework.

## Non-Obvious Design Decisions

- **Hooks: shell scripts call hooks directly unless `--no-hooks` is passed.** `server.py` always passes `--no-hooks` and runs hooks itself via `_run_hooks()`. New scripts that mutate data should follow the same pattern: call hooks unless `--no-hooks` is set.
- **UI text is Traditional Chinese; script output and error messages are English.**
- **`data/repairs/` uses a flat layout** (e.g. `data/repairs/CAM-20260305-FM-001/`). Each item directory sits directly under `data/repairs/`.
- **`web/_data/` and `web/customer/` are build-generated and .gitignored.** Do not try to commit or source-control them.
- **`page_password` frontmatter field:** a non-empty value marks a repair as having a published customer-facing page.

## Environments

- **Local dev:** `server.py` and shell scripts scan `data/repairs/` recursively.
- **Production (Cloudflare):** Cloudflare Pages serves `web/`; a Cloudflare Worker handles auth and the API.
