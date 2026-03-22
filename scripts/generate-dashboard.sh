#!/usr/bin/env bash
# scripts/generate-dashboard.sh — Generate kanban dashboard HTML
#
# Usage: generate-dashboard.sh <data-dir> <web-dir>
# Reads all items via parse-item.sh, groups by status,
# writes web/dashboard.html

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -eq 2 ]] || { echo "ERROR: Usage: generate-dashboard.sh <data-dir> <web-dir>" >&2; exit 1; }

DATA_DIR="$1"
WEB_DIR="$2"

python3 -c "
import sys, json, os, subprocess

repairs_dir = os.path.join(sys.argv[1], 'repairs')
web_dir = sys.argv[2]
parse_script = sys.argv[3]

# Collect items grouped by status
groups = {
    'not_started': [],
    'in_progress': [],
    'testing': [],
    'done': [],
    'ice_box': [],
    'delivered': [],
}

if os.path.isdir(repairs_dir):
    for name in sorted(os.listdir(repairs_dir)):
        item_md = os.path.join(repairs_dir, name, 'item.md')
        if not os.path.isfile(item_md):
            continue
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)
        status = item.get('status', '')
        if status in groups:
            groups[status].append(item)

def render_card(item):
    return (
        f'<a class=\"card\" href=\"entry.html?id={item[\"id\"]}\" data-received=\"{item[\"received_date\"]}\">'
        f'<div class=\"card-id\">{item[\"id\"]}</div>'
        f'<div class=\"card-model\">{item[\"model\"]}</div>'
        f'<div class=\"card-owner\">{item[\"owner_name\"]}</div>'
        f'<div class=\"days-badge\"></div>'
        f'</a>'
    )

def render_cards(items):
    if not items:
        return '<div class=\"empty-column\">\u2014</div>'
    return '\n'.join(render_card(item) for item in items)

columns = [
    ('not_started', '未開始'),
    ('in_progress', '進行中'),
    ('testing', '測試中'),
    ('done', '完成\u30fb待取件'),
]

columns_html = ''
for status, label in columns:
    items = groups[status]
    columns_html += f'''
    <div class=\"column\">
      <div class=\"column-header\">{label} <span class=\"count\">({len(items)})</span></div>
      <div class=\"column-cards\">
        {render_cards(items)}
      </div>
    </div>'''

ice_items = groups['ice_box']
ice_html = render_cards(ice_items)

html = f'''<!DOCTYPE html>
<html lang=\"zh-Hant\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>維修進度看板</title>
  <link rel=\"stylesheet\" href=\"static/style.css\">
</head>
<body>
  <nav class=\"toolbar\">
    <a href=\"entry.html\">維修單</a>
    <a href=\"dashboard.html\" class=\"active\">看板</a>
  </nav>
  <main class=\"kanban\">{columns_html}
  </main>
  <section class=\"ice-box collapsed\">
    <h2 class=\"section-toggle\" onclick=\"this.parentElement.classList.toggle(\'collapsed\')\">
      冰箱 <span class=\"count\">({len(ice_items)})</span>
    </h2>
    <div class=\"section-cards\">
      {ice_html}
    </div>
  </section>
  <script src=\"static/dashboard.js\"></script>
</body>
</html>'''

os.makedirs(web_dir, exist_ok=True)
with open(os.path.join(web_dir, 'dashboard.html'), 'w') as f:
    f.write(html)
" "$DATA_DIR" "$WEB_DIR" "$SCRIPT_DIR/parse-item.sh"
