// Shared fetch helper -- always sends cookies, always parses JSON,
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
  // Only apply the topbar avatar/nav from endpoints that describe the
  // CURRENTLY LOGGED IN person -- checking the request PATH here (not just
  // the response shape) is what prevents someone else's photo (e.g. from
  // viewing a staff profile in Directory) from leaking into your own
  // avatar spot.
  const isSelfInfoEndpoint = path === '/dashboard-check' || path === '/settings/me';
  if (isSelfInfoEndpoint) {
    if (data.staff) {
      applyTopbarAvatar(data.staff.photoUrl, data.staff.fullName);
      applyRoleBasedNav(data.staff.role);
    }
    if (data.profile) {
      applyTopbarAvatar(data.profile.photoUrl, data.profile.fullName);
    }
  }
  return data;
}

function initials(name) {
  if (!name) return '?';
  return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
}

// Shows the real uploaded photo if there is one. Otherwise, instead of
// falling back to the MACDEN logo (which duplicated the one already in the
// sidebar), shows initials -- same pattern already used in Directory/Settings.
function applyTopbarAvatar(photoUrl, fullName) {
  const img = document.getElementById('topbarAvatarImg');
  if (!img) return;

  if (photoUrl) {
    img.src = photoUrl;
    img.style.display = '';
  } else {
    img.style.display = 'none';
    let fallback = document.getElementById('topbarAvatarFallback');
    if (!fallback) {
      fallback = document.createElement('div');
      fallback.id = 'topbarAvatarFallback';
      fallback.style.cssText = 'width:36px;height:36px;border-radius:50%;background:var(--gold-dim);color:#a17a00;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:700;';
      img.parentNode.insertBefore(fallback, img);
    }
    fallback.textContent = initials(fullName);
    fallback.style.display = 'flex';
  }
}

// Hides sidebar links meant only for admins (currently just Broadcasts) if
// the logged-in person isn't one -- previously visible to everyone but
// dead-ended in an error page for regular staff.
function applyRoleBasedNav(role) {
  if (role === 'admin') return;
  document.querySelectorAll('a[href="broadcasts.html"]').forEach(link => {
    link.style.display = 'none';
  });
}

function showAlert(el, message, type = 'error') {
  el.textContent = message;
  el.className = `alert alert-${type} visible`;
}
function hideAlert(el) {
  el.className = 'alert';
}
async function loadUnreadBadge() {
  const badge = document.getElementById('unreadBadge');
  if (!badge) return;
  try {
    const result = await apiRequest('/messages/unread-count');
    badge.textContent = result.unreadCount;
    badge.style.display = result.unreadCount > 0 ? 'flex' : 'none';
  } catch (err) {
    // Fail silently -- badge just stays at its last known state
  }
}


// ---- Shared live-update polling engine ----
// Every portal page loads this file, so this activates everywhere with
// no per-page setup. Checks unread-count periodically; since a new
// announcement is just a broadcast message, this single check covers
// both new inbox messages and new dashboard announcements. Fires
// 'macden:newActivity' only on a genuine increase -- never on first
// load (no baseline yet) and never on a decrease (e.g. read elsewhere).
(function(){
  let lastKnownCount = null;

  async function macdenPollForUpdates() {
    try {
      const result = await apiRequest('/messages/unread-count');
      const count = result.unreadCount;

      const badge = document.getElementById('unreadBadge');
      const dot = document.getElementById('notifDot');
      if (badge) {
        badge.textContent = count;
        badge.style.display = count > 0 ? 'inline-block' : 'none';
      }
      if (dot) {
        dot.textContent = count;
        dot.style.display = count > 0 ? 'flex' : 'none';
      }

      if (lastKnownCount !== null && count > lastKnownCount) {
        window.dispatchEvent(new CustomEvent('macden:newActivity', { detail: { unreadCount: count } }));
      }
      lastKnownCount = count;
    } catch (err) {
      // Fail silently -- next poll tries again, doesn't disrupt the page
    }
  }

  setTimeout(macdenPollForUpdates, 4000);
  setInterval(macdenPollForUpdates, 20000);
})();
