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
  const pill = e.target.closest('.status-pill');
  if (!pill || !selectMode) return;
  if (pill.classList.contains('disabled')) return;

  const status = pill.getAttribute('data-status');
  const label = pill.textContent;
  const count = selectedIds.length;

  if (!confirm('確定移動 ' + count + ' 件到 ' + label + '？')) return;

  const ids = selectedIds.slice();
  let succeeded = 0;
  let i = 0;

  function next() {
    if (i >= ids.length) {
      location.reload();
      return;
    }
    const id = ids[i];
    i++;
    fetch('/api/update', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: id, status: status })
    }).then(function(res) {
      if (!res.ok) throw new Error('HTTP ' + res.status);
      succeeded++;
      next();
    }).catch(function() {
      const failed = ids.length - succeeded;
      alert('完成 ' + succeeded + ' 件，失敗 ' + failed + ' 件');
      location.reload();
    });
  }

  next();
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
