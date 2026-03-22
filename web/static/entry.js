// web/static/entry.js — Entry page logic

(function() {
  'use strict';

  let allItems = [];
  let allOwners = [];
  let currentItemId = null;
  let originalCost = null;

  function todayISO() { return todayISO(); }

  // --- Init ---
  document.addEventListener('DOMContentLoaded', async function() {
    await Promise.all([loadItems(), loadOwners()]);
    checkEditMode();
    setupSearch();
    setupOwnerAutocomplete();
    setupForm();
  });

  // --- Load data ---
  async function loadItems() {
    const res = await fetch('/api/items');
    allItems = await res.json();
  }

  async function loadOwners() {
    const res = await fetch('/api/owners');
    allOwners = await res.json();
  }

  // --- Edit mode via query param ---
  function checkEditMode() {
    const params = new URLSearchParams(window.location.search);
    const id = params.get('id');
    if (id) {
      loadItemForEdit(id);
    }
  }

  async function loadItemForEdit(id) {
    const res = await fetch('/api/item/' + encodeURIComponent(id) + '/raw');
    if (!res.ok) {
      alert('找不到維修單: ' + id);
      return;
    }
    const markdown = await res.text();
    const parsed = parseItemMarkdown(markdown);
    currentItemId = id;
    populateForm(parsed);
    showEditMode();
  }

  // --- Parse item.md in JS ---
  function parseItemMarkdown(md) {
    const result = { frontmatter: {}, description: '', costRows: [] };

    // Extract frontmatter
    const fmMatch = md.match(/^---\n([\s\S]*?)\n---/);
    if (fmMatch) {
      fmMatch[1].split('\n').forEach(function(line) {
        const colonIdx = line.indexOf(':');
        if (colonIdx > 0) {
          const key = line.substring(0, colonIdx).trim();
          let value = line.substring(colonIdx + 1).trim();
          // Remove surrounding quotes
          if (value.startsWith('"') && value.endsWith('"')) {
            value = value.slice(1, -1);
          }
          result.frontmatter[key] = value;
        }
      });
    }

    // Extract description
    const descMatch = md.match(/# 維修描述\n\n([\s\S]*?)(?=\n# |$)/);
    if (descMatch) {
      result.description = descMatch[1].trim();
    }

    // Extract cost rows
    const costMatch = md.match(/# 費用紀錄\n\n\| 日期[\s\S]*?\n\|[-|\s]+\n([\s\S]*?)$/);
    if (costMatch) {
      costMatch[1].trim().split('\n').forEach(function(line) {
        if (line.startsWith('|')) {
          const cells = line.split('|').map(function(c) { return c.trim(); }).filter(Boolean);
          if (cells.length === 3) {
            result.costRows.push({ date: cells[0], amount: cells[1], note: cells[2] });
          }
        }
      });
    }

    return result;
  }

  function populateForm(parsed) {
    const fm = parsed.frontmatter;
    document.getElementById('category').value = fm.category || '';
    document.getElementById('brand').value = fm.brand || '';
    document.getElementById('model').value = fm.model || '';
    document.getElementById('serial').value = fm.serial_number || '';
    document.getElementById('owner-name').value = fm.owner_name || '';
    document.getElementById('owner-contact').value = fm.owner_contact || '';
    document.getElementById('description').value = parsed.description || '';
    document.getElementById('status').value = fm.status || '';

    const lastRow = parsed.costRows[parsed.costRows.length - 1];
    if (lastRow) {
      document.getElementById('cost-amount').value = lastRow.amount;
      document.getElementById('cost-note').value = lastRow.note;
      originalCost = { amount: lastRow.amount, note: lastRow.note };
    } else {
      originalCost = { amount: '', note: '' };
    }
    renderCostHistory(parsed.costRows);
  }

  function renderCostHistory(rows) {
    const container = document.getElementById('cost-history');
    if (!container || rows.length === 0) return;
    var table = document.createElement('table');
    var thead = document.createElement('thead');
    var headRow = document.createElement('tr');
    ['日期', '金額', '說明'].forEach(function(text) {
      var th = document.createElement('th');
      th.textContent = text;
      headRow.appendChild(th);
    });
    thead.appendChild(headRow);
    table.appendChild(thead);
    var tbody = document.createElement('tbody');
    rows.forEach(function(r) {
      var tr = document.createElement('tr');
      [r.date, r.amount, r.note].forEach(function(text) {
        var td = document.createElement('td');
        td.textContent = text;
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    table.appendChild(tbody);
    container.innerHTML = '';
    container.appendChild(table);
  }

  function showEditMode() {
    document.body.classList.add('edit-mode');
    document.getElementById('status-group').style.display = '';
    document.getElementById('open-logs-btn').style.display = '';
    document.getElementById('submit-btn').textContent = '更新維修單';
  }

  // --- Search ---
  function setupSearch() {
    const input = document.getElementById('search');
    const results = document.getElementById('search-results');
    if (!input || !results) return;

    input.addEventListener('input', function() {
      const q = input.value.toLowerCase();
      if (q.length < 1) {
        results.style.display = 'none';
        return;
      }
      const matches = allItems.filter(function(item) {
        return item.id.toLowerCase().includes(q) ||
               item.model.toLowerCase().includes(q) ||
               item.owner_name.toLowerCase().includes(q);
      });
      if (matches.length === 0) {
        results.style.display = 'none';
        return;
      }
      results.innerHTML = '';
      matches.forEach(function(item) {
        var div = document.createElement('div');
        div.className = 'search-result';
        div.dataset.id = item.id;
        div.textContent = item.id + ' — ' + item.model + ' (' + item.owner_name + ')';
        div.addEventListener('click', function() {
          window.location.href = 'entry.html?id=' + encodeURIComponent(item.id);
        });
        results.appendChild(div);
      });
      results.style.display = '';
    });
  }

  // --- Owner autocomplete ---
  function setupOwnerAutocomplete() {
    const nameInput = document.getElementById('owner-name');
    const contactInput = document.getElementById('owner-contact');
    const suggestions = document.getElementById('owner-suggestions');
    if (!nameInput || !suggestions) return;

    nameInput.addEventListener('input', function() {
      const q = nameInput.value.toLowerCase();
      if (q.length < 1) {
        suggestions.style.display = 'none';
        return;
      }
      const matches = allOwners.filter(function(o) {
        return o.name.toLowerCase().includes(q) || o.contact.toLowerCase().includes(q);
      });
      if (matches.length === 0) {
        suggestions.style.display = 'none';
        return;
      }
      suggestions.innerHTML = '';
      matches.forEach(function(o) {
        var div = document.createElement('div');
        div.className = 'suggestion';
        div.textContent = o.name + ' — ' + o.contact;
        div.addEventListener('click', function() {
          nameInput.value = o.name;
          contactInput.value = o.contact;
          suggestions.style.display = 'none';
        });
        suggestions.appendChild(div);
      });
      suggestions.style.display = '';
    });
  }

  // --- Form submission ---
  function setupForm() {
    const form = document.getElementById('repair-form');
    if (!form) return;

    form.addEventListener('submit', async function(e) {
      e.preventDefault();
      if (currentItemId) {
        await submitUpdate();
      } else {
        await submitCreate();
      }
    });

    // Open logs button
    const logsBtn = document.getElementById('open-logs-btn');
    if (logsBtn) {
      logsBtn.addEventListener('click', function() {
        if (currentItemId) {
          fetch('/api/open-logs/' + encodeURIComponent(currentItemId));
        }
      });
    }
  }

  async function submitCreate() {
    const data = {
      category: document.getElementById('category').value,
      brand: document.getElementById('brand').value,
      model: document.getElementById('model').value,
      serial_number: document.getElementById('serial').value,
      owner_name: document.getElementById('owner-name').value,
      owner_contact: document.getElementById('owner-contact').value,
      description: document.getElementById('description').value,
      date: todayISO(),
    };

    const amount = document.getElementById('cost-amount').value;
    const note = document.getElementById('cost-note').value;
    if (amount && note) {
      data.cost_amount = amount;
      data.cost_note = note;
    }

    const res = await fetch('/api/create', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    const result = await res.json();
    if (res.ok) {
      window.location.href = 'entry.html?id=' + result.id;
    } else {
      alert('建立失敗: ' + result.error);
    }
  }

  async function submitUpdate() {
    const data = {
      id: currentItemId,
      status: document.getElementById('status').value,
      owner_name: document.getElementById('owner-name').value,
      owner_contact: document.getElementById('owner-contact').value,
      description: document.getElementById('description').value,
      brand: document.getElementById('brand').value,
      serial_number: document.getElementById('serial').value,
    };

    // Check if cost changed — if so, append a cost change log entry
    const newAmount = document.getElementById('cost-amount').value;
    const newNote = document.getElementById('cost-note').value;
    if (originalCost && (newAmount !== originalCost.amount || newNote !== originalCost.note)) {
      data.cost_amount = newAmount;
      data.cost_note = newNote;
      data.cost_date = todayISO();
    }

    // Auto-set delivered_date
    if (data.status === 'delivered') {
      data.delivered_date = todayISO();
    }

    const res = await fetch('/api/update', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    const result = await res.json();
    if (res.ok) {
      window.location.reload();
    } else {
      alert('更新失敗: ' + result.error);
    }
  }
})();
