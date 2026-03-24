// web/static/dashboard.js — Compute days since received for each card

document.addEventListener('DOMContentLoaded', function() {
  const cards = document.querySelectorAll('[data-received]');
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  cards.forEach(function(card) {
    const received = new Date(card.getAttribute('data-received'));
    received.setHours(0, 0, 0, 0);
    const days = Math.floor((today - received) / (1000 * 60 * 60 * 24));
    const badge = card.querySelector('.days-badge');
    if (badge) {
      badge.textContent = days + ' 天';
    }
  });
});

// --- Selection Mode ---
let selectMode = false;
let selectedIds = [];

function toggleSelectMode() {
  selectMode = !selectMode;
  const toggle = document.querySelector('.select-toggle');
  const moveBar = document.querySelector('.move-bar');

  if (selectMode) {
    document.body.classList.add('selecting');
    toggle.classList.add('active');
    toggle.textContent = '取消選取';
    moveBar.style.display = '';
    updateMoveBar();
  } else {
    document.body.classList.remove('selecting');
    toggle.classList.remove('active');
    toggle.textContent = '選取';
    moveBar.style.display = 'none';
    clearSelection();
  }
}

function clearSelection() {
  selectedIds = [];
  document.querySelectorAll('.card.selected').forEach(function(card) {
    card.classList.remove('selected');
  });
}

function updateMoveBar() {
  const countEl = document.querySelector('.move-bar-count');
  if (countEl) {
    countEl.textContent = '已選 ' + selectedIds.length + ' 件 — 移動到：';
  }
  document.querySelectorAll('.status-pill').forEach(function(pill) {
    if (selectedIds.length === 0) {
      pill.classList.add('disabled');
    } else {
      pill.classList.remove('disabled');
    }
  });
}

document.addEventListener('click', function(e) {
  if (!selectMode) return;

  const card = e.target.closest('.card');
  if (!card) return;

  e.preventDefault();

  const itemId = card.getAttribute('data-item-id');
  if (!itemId) return;

  const idx = selectedIds.indexOf(itemId);
  if (idx === -1) {
    selectedIds.push(itemId);
    card.classList.add('selected');
  } else {
    selectedIds.splice(idx, 1);
    card.classList.remove('selected');
  }
  updateMoveBar();
});

document.addEventListener('click', function(e) {
  var pill = e.target.closest('.status-pill');
  if (!pill || !selectMode) return;
  if (pill.classList.contains('disabled')) return;

  var status = pill.getAttribute('data-status');
  var label = pill.textContent;
  var count = selectedIds.length;

  if (!confirm('確定移動 ' + count + ' 件到 ' + label + '？')) return;

  var updates = selectedIds.map(function(id) {
    return { id: id, status: status };
  });

  fetch('/api/batch-update', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ updates: updates })
  }).then(function(res) {
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return res.json();
  }).then(function(data) {
    var isLocal = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
    var msg = '儲存成功';
    if (!isLocal) msg += '，頁面資料將在數分鐘內更新';
    if (data.failed && data.failed.length > 0) {
      msg += '\n（' + data.failed.length + ' 件失敗）';
    }
    alert(msg);
    location.reload();
  }).catch(function() {
    alert('批次更新失敗，請重試');
    location.reload();
  });
});

function toggleIceBox(el) {
  const iceBox = el.parentElement;
  iceBox.classList.toggle('collapsed');

  if (selectMode && iceBox.classList.contains('collapsed')) {
    iceBox.querySelectorAll('.card.selected').forEach(function(card) {
      const itemId = card.getAttribute('data-item-id');
      const idx = selectedIds.indexOf(itemId);
      if (idx !== -1) {
        selectedIds.splice(idx, 1);
      }
      card.classList.remove('selected');
    });
    updateMoveBar();
  }
}
