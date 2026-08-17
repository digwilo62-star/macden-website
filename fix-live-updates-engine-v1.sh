#!/bin/bash
# fix-live-updates-engine-v1.sh
#
# Adds a shared live-update polling engine to api.js, which every portal
# page already loads -- so this activates portal-wide with no per-page
# duplication. Checks the existing unread-count endpoint every ~20
# seconds (same interval as the connection watchdog). Since a new
# announcement is just a broadcast message, this single lightweight
# check naturally covers both new inbox messages AND new announcements.
#
# Fires a 'macden:newActivity' browser event whenever the count genuinely
# increases (never on first load, never on a decrease) -- individual
# pages listen for this to refresh their own content. Also keeps the
# notification badge updated automatically wherever it exists on a page.
#
# Verified against a range of scenarios (baseline, increase, decrease,
# no-change) before shipping.

set -e

if grep -q "macden:newActivity" portal/assets/api.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat >> portal/assets/api.js << 'ENGINE_EOF'

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
ENGINE_EOF

echo "    Added live-update polling engine to portal/assets/api.js."
echo ""
echo "Done. Push with your usual save-progress.sh."
