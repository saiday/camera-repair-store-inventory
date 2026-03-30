#!/usr/bin/env python3
"""HTTP server for the camera repair shop inventory system.

Uses only Python standard library. Serves static files from web/ and
handles API endpoints by calling shell scripts.

Usage: python3 server.py --port 8787 --data-dir data --web-dir web --scripts-dir scripts
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
from datetime import date
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

_ITEM_ID_RE = re.compile(r'^[A-Za-z0-9-]+$')


class InventoryHandler(SimpleHTTPRequestHandler):
    """Custom handler for the inventory system."""

    def __init__(self, *args, data_dir, web_dir, scripts_dir, **kwargs):
        self.data_dir = data_dir
        self.web_dir = web_dir
        self.scripts_dir = scripts_dir
        super().__init__(*args, directory=web_dir, **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/' or path == '':
            # Serve dashboard.html as landing page
            self.path = '/dashboard.html'
            return super().do_GET()
        elif path == '/api/items':
            self._handle_get_items()
        elif path == '/api/owners':
            self._handle_get_owners()
        elif path.startswith('/api/item/') and path.endswith('/raw'):
            item_id = path[len('/api/item/'):-len('/raw')]
            self._handle_get_item_raw(item_id)
        elif path.startswith('/api/open-logs/'):
            item_id = path[len('/api/open-logs/'):]
            self._handle_open_logs(item_id)
        elif path == '/_data/items.json':
            self._handle_get_items()
        elif path == '/_data/owners.json':
            self._handle_get_owners()
        elif path.startswith('/_data/items/') and path.endswith('.json'):
            item_id = path[len('/_data/items/'):-len('.json')]
            self._handle_get_item_json(item_id)
        elif path.startswith('/item/'):
            item_id = path[len('/item/'):]
            self.path = '/customer/' + item_id + '.html'
            return super().do_GET()
        else:
            super().do_GET()

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode('utf-8')

        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            self._send_json(400, {'error': 'Invalid JSON'})
            return

        if path == '/api/create':
            self._handle_create(data)
        elif path == '/api/update':
            self._handle_update(data)
        elif path == '/api/deliver':
            self._handle_deliver(data)
        elif path == '/api/batch-update':
            self._handle_batch_update(data)
        else:
            self._send_json(404, {'error': 'Not found'})

    def _handle_get_items(self):
        """Return all items as JSON (frontmatter only)."""
        repairs_dir = os.path.join(self.data_dir, 'repairs')
        items = []
        if os.path.isdir(repairs_dir):
            for item_md in sorted(glob.glob(os.path.join(repairs_dir, '**', 'item.md'), recursive=True)):
                result = subprocess.run(
                    [os.path.join(self.scripts_dir, 'parse-item.sh'), item_md],
                    capture_output=True, text=True
                )
                if result.returncode == 0:
                    items.append(json.loads(result.stdout))
        self._send_json(200, items)

    def _handle_get_owners(self):
        """Return owners.json."""
        owners_file = os.path.join(self.data_dir, 'owners.json')
        if os.path.isfile(owners_file):
            with open(owners_file, 'r') as f:
                self._send_json(200, json.load(f))
        else:
            self._send_json(200, [])

    def _find_item_dir(self, item_id):
        """Find item directory by ID across nested YYYY/MM/ structure."""
        if not _ITEM_ID_RE.match(item_id):
            return None
        repairs_dir = os.path.join(self.data_dir, 'repairs')
        for item_md in glob.glob(os.path.join(repairs_dir, '**', item_id, 'item.md'), recursive=True):
            resolved = os.path.realpath(os.path.dirname(item_md))
            if resolved.startswith(os.path.realpath(repairs_dir) + os.sep):
                return os.path.dirname(item_md)
        return None

    def _handle_get_item_raw(self, item_id):
        """Return raw item.md content."""
        item_dir = self._find_item_dir(item_id)
        if item_dir is None:
            self._send_json(400, {'error': 'Invalid item ID'})
            return
        item_md = os.path.join(item_dir, 'item.md')
        if os.path.isfile(item_md):
            with open(item_md, 'r') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/markdown; charset=utf-8')
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))
        else:
            self._send_json(404, {'error': f'Item not found: {item_id}'})

    def _handle_get_item_json(self, item_id):
        """Return full parsed JSON for a single item (including description and cost rows)."""
        item_dir = self._find_item_dir(item_id)
        if item_dir is None:
            self._send_json(400, {'error': 'Invalid item ID'})
            return
        item_md = os.path.join(item_dir, 'item.md')
        if not os.path.isfile(item_md):
            self._send_json(404, {'error': f'Item not found: {item_id}'})
            return
        result = subprocess.run(
            [os.path.join(self.scripts_dir, 'parse-item.sh'), item_md],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            self._send_json(200, json.loads(result.stdout))
        else:
            self._send_json(500, {'error': result.stderr.strip()})

    def _handle_open_logs(self, item_id):
        """Open the item's logs folder in Finder."""
        item_dir = self._find_item_dir(item_id)
        if item_dir is None:
            self._send_json(400, {'error': 'Invalid item ID'})
            return
        logs_dir = os.path.join(item_dir, 'logs')
        os.makedirs(logs_dir, exist_ok=True)
        subprocess.Popen(['open', logs_dir])
        self._send_json(200, {'ok': True})

    def _handle_create(self, data):
        """Create a new repair item."""
        item_date = data.get('date') or date.today().isoformat()
        cmd = [
            os.path.join(self.scripts_dir, 'create-item.sh'),
            '--no-hooks',
            '--data-dir', self.data_dir,
            '--category', data.get('category', ''),
            '--brand', data.get('brand', ''),
            '--model', data.get('model', ''),
            '--serial', data.get('serial_number', ''),
            '--owner-name', data.get('owner_name', ''),
            '--owner-contact', data.get('owner_contact', ''),
            '--description', data.get('description', ''),
            '--date', item_date,
        ]
        if data.get('cost_amount') and data.get('cost_note'):
            cmd += ['--cost-amount', str(data['cost_amount']), '--cost-note', data['cost_note']]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            item_id = result.stdout.strip()
            # Run hooks
            self._run_hooks(item_id)
            self._send_json(200, {'id': item_id})
        else:
            self._send_json(400, {'error': result.stderr.strip()})

    def _handle_update(self, data):
        """Update an existing item."""
        item_id = data.get('id', '')
        item_dir = self._find_item_dir(item_id)
        if item_dir is None:
            self._send_json(400, {'error': 'Invalid item ID'})
            return

        if not os.path.isdir(item_dir):
            self._send_json(404, {'error': f'Item not found: {item_id}'})
            return

        cmd = [os.path.join(self.scripts_dir, 'update-item.sh'), '--no-hooks', '--item-dir', item_dir]

        field_map = {
            'status': '--status',
            'owner_name': '--owner-name',
            'owner_contact': '--owner-contact',
            'description': '--description',
            'brand': '--brand',
            'serial_number': '--serial',
        }
        for field, flag in field_map.items():
            if data.get(field) not in (None, ''):
                cmd += [flag, str(data[field])]

        # page_password: pass through even when empty (to allow clearing)
        if 'page_password' in data and data['page_password'] is not None:
            cmd += ['--page-password', str(data['page_password'])]

        if data.get('cost_amount') and data.get('cost_note'):
            cmd += [
                '--cost-amount', str(data['cost_amount']),
                '--cost-note', data['cost_note'],
                '--cost-date', data.get('cost_date', ''),
            ]

        if data.get('delivered_date'):
            cmd += ['--delivered-date', data['delivered_date']]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            self._run_hooks(item_id)
            self._send_json(200, {'ok': True, 'id': item_id})
        else:
            self._send_json(400, {'error': result.stderr.strip()})

    def _handle_deliver(self, data):
        """Mark an item as delivered."""
        data['status'] = 'delivered'
        if 'delivered_date' not in data:
            data['delivered_date'] = date.today().isoformat()
        self._handle_update(data)

    def _handle_batch_update(self, data):
        """Batch update multiple items, running hooks only once."""
        updates = data.get('updates')
        if not isinstance(updates, list) or len(updates) == 0:
            self._send_json(400, {'error': 'updates must be a non-empty array'})
            return
        if len(updates) > 50:
            self._send_json(400, {'error': 'Too many updates (max 50)'})
            return
        ids = [u.get('id', '') for u in updates]
        if len(set(ids)) != len(ids):
            self._send_json(400, {'error': 'Duplicate IDs in batch'})
            return

        succeeded = []
        failed = []
        for entry in updates:
            item_id = entry.get('id', '')
            item_dir = self._find_item_dir(item_id)
            if item_dir is None or not os.path.isdir(item_dir):
                failed.append(item_id)
                continue

            cmd = [os.path.join(self.scripts_dir, 'update-item.sh'), '--no-hooks', '--item-dir', item_dir]

            field_map = {
                'status': '--status',
                'owner_name': '--owner-name',
                'owner_contact': '--owner-contact',
                'description': '--description',
                'brand': '--brand',
                'serial_number': '--serial',
            }
            for field, flag in field_map.items():
                if entry.get(field) not in (None, ''):
                    cmd += [flag, str(entry[field])]

            # page_password: pass through even when empty (to allow clearing)
            if 'page_password' in entry and entry['page_password'] is not None:
                cmd += ['--page-password', str(entry['page_password'])]

            if entry.get('cost_amount') and entry.get('cost_note'):
                cmd += [
                    '--cost-amount', str(entry['cost_amount']),
                    '--cost-note', entry['cost_note'],
                    '--cost-date', entry.get('cost_date', ''),
                ]

            if entry.get('delivered_date'):
                cmd += ['--delivered-date', entry['delivered_date']]

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                succeeded.append(item_id)
            else:
                failed.append(item_id)

        # Run hooks once
        if succeeded:
            self._run_hooks(succeeded[0])

        if not succeeded:
            self._send_json(400, {'error': 'All items failed', 'failed': failed})
        elif failed:
            self._send_json(200, {'ok': False, 'error': 'Some items failed', 'succeeded': succeeded, 'failed': failed})
        else:
            self._send_json(200, {'ok': True, 'ids': succeeded})

    def _run_hooks(self, item_id):
        """Run post-mutation hooks in parallel: update owners, regenerate dashboard."""
        p1 = subprocess.Popen(
            [os.path.join(self.scripts_dir, 'update-owners.sh'), self.data_dir],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        p2 = subprocess.Popen(
            [os.path.join(self.scripts_dir, 'generate-dashboard.sh'), self.data_dir, self.web_dir],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        p1.wait()
        p2.wait()

    def _send_json(self, status_code, data):
        """Send a JSON response."""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def address_string(self):
        """Skip reverse DNS lookup to avoid slow responses on macOS."""
        return self.client_address[0]

    def log_message(self, format, *args):
        """Suppress default access log to stderr."""
        pass


def make_handler(data_dir, web_dir, scripts_dir):
    """Create a handler class with the given directories."""
    def handler(*args, **kwargs):
        return InventoryHandler(
            *args,
            data_dir=data_dir,
            web_dir=web_dir,
            scripts_dir=scripts_dir,
            **kwargs
        )
    return handler


def main():
    parser = argparse.ArgumentParser(description='Camera Repair Inventory Server')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--data-dir', default='data')
    parser.add_argument('--web-dir', default='web')
    parser.add_argument('--scripts-dir', default='scripts')
    args = parser.parse_args()

    # Resolve to absolute paths
    data_dir = os.path.abspath(args.data_dir)
    web_dir = os.path.abspath(args.web_dir)
    scripts_dir = os.path.abspath(args.scripts_dir)

    handler = make_handler(data_dir, web_dir, scripts_dir)
    server = HTTPServer(('127.0.0.1', args.port), handler)

    print(f"Server running at http://localhost:{args.port}")
    print(f"  Data: {data_dir}")
    print(f"  Web:  {web_dir}")
    print(f"Press Ctrl+C to stop.")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()


if __name__ == '__main__':
    main()
