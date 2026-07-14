// Shared fetch helper — always sends cookies, always parses JSON,
// throws a readable error message so pages can show it directly.
async function apiRequest(path, options = {}) {
  const res = await fetch(`/api/accounting${path}`, {
    method: options.method || 'GET',
    headers: { 'Content-Type': 'application/json' },
    credentials: 'include',
    body: options.body ? JSON.stringify(options.body) : undefined
  });

  const data = await res.json();

  if (!res.ok) {
    throw new Error(data.error || 'Something went wrong.');
  }

  return data;
}

function showAlert(el, message, type = 'error') {
  el.textContent = message;
  el.className = `alert alert-${type} visible`;
}

function hideAlert(el) {
  el.className = 'alert';
}

// Shared across every page with the hamburger nav — keeps the unread badge live.
async function loadUnreadBadge() {
  const badge = document.getElementById('unreadBadge');
  if (!badge) return;
  try {
    const result = await apiRequest('/messages/unread-count');
    badge.textContent = result.unreadCount;
    badge.style.display = result.unreadCount > 0 ? 'flex' : 'none';
  } catch (err) {
    // Fail silently — badge just stays at its last known state
  }
}

