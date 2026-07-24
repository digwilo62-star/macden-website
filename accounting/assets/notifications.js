// Shared notification bell dropdown — loaded on every portal page.
// Requires this markup to exist in the topbar:
// <div class="notif-wrap">
//   <button class="topbar-bell" id="notifBell"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
//   <div class="notif-dropdown" id="notifDropdown">...</div>
// </div>

async function initNotificationBell() {
  const bell = document.getElementById('notifBell');
  const dropdown = document.getElementById('notifDropdown');
  if (!bell || !dropdown) return;

  await refreshNotifBadge();

  bell.addEventListener('click', async (e) => {
    e.stopPropagation();
    const isOpen = dropdown.classList.contains('visible');
    if (isOpen) {
      dropdown.classList.remove('visible');
      return;
    }
    dropdown.classList.add('visible');
    await loadNotifDropdown();
  });

  document.addEventListener('click', (e) => {
    if (!e.target.closest('.notif-wrap')) {
      dropdown.classList.remove('visible');
    }
  });
}

async function refreshNotifBadge() {
  try {
    const result = await apiRequest('/notifications');
    const dot = document.getElementById('notifDot');
    if (result.unreadCount > 0) {
      dot.textContent = result.unreadCount;
      dot.style.display = 'flex';
    } else {
      dot.style.display = 'none';
    }
  } catch (err) {}
}

async function loadNotifDropdown() {
  const dropdown = document.getElementById('notifDropdown');
  dropdown.innerHTML = '<div class="notif-empty">Loading…</div>';

  try {
    const result = await apiRequest('/notifications');

    if (result.notifications.length === 0) {
      dropdown.innerHTML = '<div class="notif-header">Notifications</div><div class="notif-empty">Nothing new right now.</div>';
      return;
    }

    const items = result.notifications.map(n =>
      '<a href="' + n.link + '" class="notif-item">' +
        '<div class="notif-icon"><i class="ti ' + n.icon + '"></i></div>' +
        '<div class="notif-text">' +
          '<div class="notif-title">' + n.title + '</div>' +
          '<div class="notif-detail">' + n.detail + '</div>' +
          '<div class="notif-time">' + n.timeAgo + '</div>' +
        '</div>' +
      '</a>'
    ).join('');

    dropdown.innerHTML = '<div class="notif-header">Notifications</div><div class="notif-list">' + items + '</div>';
  } catch (err) {
    dropdown.innerHTML = '<div class="notif-header">Notifications</div><div class="notif-empty">Could not load notifications.</div>';
  }
}

document.addEventListener('DOMContentLoaded', initNotificationBell);

