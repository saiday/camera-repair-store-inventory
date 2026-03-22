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
