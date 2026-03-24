#!/usr/bin/env bash
# scripts/generate-dashboard.sh — Generate kanban dashboard HTML
#
# Usage: generate-dashboard.sh <data-dir> <web-dir>
# Reads all items via parse-item.sh, groups by status,
# writes web/dashboard.html

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="${1:-$SCRIPT_DIR/../data}"
WEB_DIR="${2:-$SCRIPT_DIR/../web}"

python3 -c "
import sys, json, os, subprocess, html, glob

repairs_dir = os.path.join(sys.argv[1], 'repairs')
web_dir = sys.argv[2]
parse_script = sys.argv[3]

groups = {
    'not_started': [],
    'in_progress': [],
    'testing': [],
    'done': [],
    'ice_box': [],
}

if os.path.isdir(repairs_dir):
    for item_md in sorted(glob.glob(os.path.join(repairs_dir, '**', 'item.md'), recursive=True)):
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)
        status = item.get('status', '')
        if status in groups:
            groups[status].append(item)

for items in groups.values():
    items.sort(key=lambda x: x.get('received_date', ''))

def render_card(item):
    eid = html.escape(item['id'])
    ebrand = html.escape(item['brand'])
    emodel = html.escape(item['model'])
    eserial = html.escape(item['serial_number'])
    eowner = html.escape(item['owner_name'])
    edate = html.escape(item['received_date'])
    edesc = html.escape(item.get('description', ''))
    serial_html = f'<span class=\"card-serial\">{eserial}</span>' if eserial else ''
    desc_html = f'<div class=\"card-desc\">{edesc}</div>' if edesc else ''
    return (
        f'<a class=\"card\" href=\"entry.html?id={eid}\" data-received=\"{edate}\" data-item-id=\"{eid}\">'
        f'<div class=\"card-id\">{eid}</div>'
        f'<div class=\"card-model\">{ebrand} {emodel} {serial_html}</div>'
        f'<div class=\"card-owner\">{eowner}</div>'
        f'{desc_html}'
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
    <button class=\"select-toggle\" onclick=\"toggleSelectMode()\">選取</button>
  </nav>
  <main class=\"kanban\">{columns_html}
  </main>
  <section class=\"ice-box collapsed\">
    <h2 class=\"section-toggle\" onclick=\"toggleIceBox(this)\">
      冰箱 <span class=\"count\">({len(ice_items)})</span>
    </h2>
    <div class=\"section-cards\">
      {ice_html}
    </div>
  </section>
  <div class=\"move-bar\" style=\"display:none\">
    <div class=\"move-bar-count\">已選 0 件 — 移動到：</div>
    <div class=\"move-bar-pills\">
      <button class=\"status-pill\" data-status=\"not_started\">未開始</button>
      <button class=\"status-pill\" data-status=\"in_progress\">進行中</button>
      <button class=\"status-pill\" data-status=\"testing\">測試中</button>
      <button class=\"status-pill\" data-status=\"done\">完成\u30fb待取件</button>
      <button class=\"status-pill\" data-status=\"ice_box\">冰箱</button>
    </div>
  </div>
  <script src=\"static/dashboard.js\"></script>
</body>
</html>'''

os.makedirs(web_dir, exist_ok=True)
with open(os.path.join(web_dir, 'dashboard.html'), 'w') as f:
    f.write(html)
" "$DATA_DIR" "$WEB_DIR" "$SCRIPT_DIR/parse-item.sh"
