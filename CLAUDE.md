# Camera Repair Shop Inventory System

## Tech Constraints

- **Bash 3.2** — macOS default. No `declare -A`, no `local -n`, no `${!var}`. Use inline Python when you need associative data structures.
- **Python 3 stdlib only** — no pip, no venv, no third-party packages.
- **Vanilla HTML/CSS/JS** — no build step, no framework.

## Non-Obvious Design Decisions

- **Hooks: shell scripts call hooks directly unless `--no-hooks` is passed.** `server.py` always passes `--no-hooks` and runs hooks itself via `_run_hooks()`. New scripts that mutate data should follow the same pattern: call hooks unless `--no-hooks` is set.
- **UI text is Traditional Chinese; script output and error messages are English.**
- **`data/repairs/` uses `YYYY/MM/` nesting** (e.g. `data/repairs/2026/03/R001/`). Agents must not assume a flat layout.
- **`web/_data/` and `web/customer/` are build-generated and .gitignored.** Do not try to commit or source-control them.
- **`page_password` frontmatter field:** a non-empty value marks a repair as having a published customer-facing page.

## Environments

- **Local dev:** `server.py` and shell scripts work as before; they scan `data/repairs/` recursively across nested `YYYY/MM/` dirs.
- **Production (Cloudflare):** Cloudflare Pages serves `web/`; a Cloudflare Worker handles auth and the API.
