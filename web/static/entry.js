// web/static/entry.js — Entry page logic

(function() {
  'use strict';

  let allItems = [];
  let allOwners = [];
  let currentItemId = null;
  let originalCost = null;

  function todayISO() { return new Date().toISOString().split('T')[0]; }

  // --- Init ---
  document.addEventListener('DOMContentLoaded', async function() {
    await Promise.all([loadItems(), loadOwners()]);
    checkEditMode();
    setupSearch();
    setupOwnerAutocomplete();
    setupForm();
    setupPublishUI();
  });

  // --- Load data ---
  async function loadItems() {
    const res = await fetch('/_data/items.json');
    allItems = await res.json();
  }

  async function loadOwners() {
    const res = await fetch('/_data/owners.json');
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
    const res = await fetch('/_data/items/' + encodeURIComponent(id) + '.json');
    if (!res.ok) { alert('找不到維修單: ' + id); return; }
    const item = await res.json();
    currentItemId = id;
    populateFormFromJson(item);
    showEditMode();
  }

  function populateFormFromJson(item) {
    document.getElementById('category').value = item.category || '';
    document.getElementById('brand').value = item.brand || '';
    document.getElementById('model').value = item.model || '';
    document.getElementById('serial').value = item.serial_number || '';
    document.getElementById('owner-name').value = item.owner_name || '';
    document.getElementById('owner-contact').value = item.owner_contact || '';
    document.getElementById('description').value = item.description || '';
    document.getElementById('status').value = item.status || '';
    document.getElementById('page-password').value = item.page_password || '';

    // Cost history from per-item JSON (cost_rows added in Task 3)
    const costRows = item.cost_rows || [];
    renderCostHistory(costRows);
    const lastRow = costRows[costRows.length - 1];
    if (lastRow) {
      document.getElementById('cost-amount').value = lastRow.amount;
      document.getElementById('cost-note').value = lastRow.note;
      originalCost = { amount: lastRow.amount, note: lastRow.note };
    } else {
      originalCost = { amount: '', note: '' };
    }
    updateShareMessage();
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
    document.getElementById('publish-section').style.display = '';
    // Hide open-logs button when not running locally (no /api/open-logs/ endpoint in production)
    if (window.location.port !== '8787') {
      document.getElementById('open-logs-btn').style.display = 'none';
    }
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
               item.brand.toLowerCase().includes(q) ||
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

  // --- Publish UI ---
  function setupPublishUI() {
    const publishBtn = document.getElementById('publish-btn');
    const pagePassword = document.getElementById('page-password');
    const copyBtn = document.getElementById('copy-share-btn');

    if (publishBtn) {
      publishBtn.addEventListener('click', function() {
        pagePassword.value = document.getElementById('owner-contact').value;
        updateShareMessage();
      });
    }
    if (pagePassword) {
      pagePassword.addEventListener('input', updateShareMessage);
    }
    if (copyBtn) {
      copyBtn.addEventListener('click', function() {
        const text = document.getElementById('share-text').textContent;
        navigator.clipboard.writeText(text);
      });
    }
  }

  function updateShareMessage() {
    const password = document.getElementById('page-password').value;
    const shareDiv = document.getElementById('share-message');
    const shareText = document.getElementById('share-text');
    if (password && currentItemId) {
      const siteUrl = window.location.origin;
      const url = siteUrl + '/item/' + currentItemId;
      shareText.textContent = '你的維修單：' + url + '，請使用 ' + password + ' 作為密碼進行查看';
      shareDiv.style.display = '';
    } else if (shareDiv) {
      shareDiv.style.display = 'none';
    }
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
      page_password: document.getElementById('page-password').value,
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
      alert('儲存成功，頁面資料將在數分鐘內更新');
      window.location.reload();
    } else {
      alert('更新失敗: ' + result.error);
    }
  }
})();
