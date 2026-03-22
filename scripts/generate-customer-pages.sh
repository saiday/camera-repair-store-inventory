#!/usr/bin/env bash
# scripts/generate-customer-pages.sh — Generate customer-facing HTML pages
#
# Usage: generate-customer-pages.sh <data-dir> <web-dir>
# Generates web/customer/{ITEM_ID}.html for each published item
# (page_password non-empty AND status != delivered)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="${1:?ERROR: data-dir required}"
WEB_DIR="${2:?ERROR: web-dir required}"

python3 -c "
import sys, json, os, subprocess, glob, html, re

data_dir = sys.argv[1]
web_dir = sys.argv[2]
parse_script = sys.argv[3]

repairs_dir = os.path.join(data_dir, 'repairs')
customer_dir = os.path.join(web_dir, 'customer')
os.makedirs(customer_dir, exist_ok=True)

count = 0
if os.path.isdir(repairs_dir):
    for item_md in sorted(glob.glob(os.path.join(repairs_dir, '**', 'item.md'), recursive=True)):
        result = subprocess.run([parse_script, item_md], capture_output=True, text=True)
        if result.returncode != 0:
            continue
        item = json.loads(result.stdout)

        # Skip unpublished or delivered
        if not item.get('page_password') or item.get('status') == 'delivered':
            continue

        # Read full markdown for cost table
        with open(item_md, 'r') as f:
            md_content = f.read()

        # Extract cost rows from markdown
        cost_html = ''
        cost_match = re.search(r'# 費用紀錄\n\n(\| 日期[\s\S]*?)$', md_content)
        if cost_match:
            cost_html = '<table><thead><tr><th>日期</th><th>金額</th><th>說明</th></tr></thead><tbody>'
            for line in cost_match.group(1).strip().split('\n')[2:]:  # skip header + separator
                cells = [c.strip() for c in line.split('|') if c.strip()]
                if len(cells) == 3:
                    cost_html += '<tr>' + ''.join(f'<td>{html.escape(c)}</td>' for c in cells) + '</tr>'
            cost_html += '</tbody></table>'

        eid = html.escape(item['id'])
        status_labels = {
            'not_started': '未開始',
            'in_progress': '進行中',
            'testing': '測試中',
            'done': '完成・待取件',
            'ice_box': '冰箱',
        }
        estatus = html.escape(status_labels.get(item['status'], item['status']))

        page_html = f'''<!DOCTYPE html>
<html lang=\"zh-Hant\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>維修進度 — {eid}</title>
  <link rel=\"stylesheet\" href=\"../static/style.css\">
</head>
<body>
  <main class=\"customer-page\">
    <h1>維修進度</h1>
    <dl class=\"item-details\">
      <dt>維修單號</dt><dd>{eid}</dd>
      <dt>類別</dt><dd>{html.escape(item['category'])}</dd>
      <dt>品牌</dt><dd>{html.escape(item['brand'])}</dd>
      <dt>型號</dt><dd>{html.escape(item['model'])}</dd>
      <dt>序號</dt><dd>{html.escape(item.get('serial_number', ''))}</dd>
      <dt>狀態</dt><dd class=\"status-{html.escape(item['status'])}\">{estatus}</dd>
      <dt>收件日期</dt><dd>{html.escape(item.get('received_date', ''))}</dd>
      <dt>交付日期</dt><dd>{html.escape(item.get('delivered_date', '') or '—')}</dd>
    </dl>
    <section class=\"repair-description\">
      <h2>維修描述</h2>
      <p>{html.escape(item.get('description', ''))}</p>
    </section>
    <section class=\"cost-log\">
      <h2>費用紀錄</h2>
      {cost_html if cost_html else '<p>尚無費用紀錄</p>'}
    </section>
  </main>
</body>
</html>'''

        with open(os.path.join(customer_dir, item['id'] + '.html'), 'w') as f:
            f.write(page_html)
        count += 1

print(f'  {count} customer pages generated')
" "$DATA_DIR" "$WEB_DIR" "$SCRIPT_DIR/parse-item.sh"
