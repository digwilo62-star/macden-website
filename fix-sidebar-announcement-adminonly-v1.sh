#!/bin/bash
# fix-sidebar-announcement-adminonly-v1.sh
#
# Hides the "Announcement" sidebar link entirely for non-admins -- they
# can't post or manage announcements, so there's no reason to show them
# a link that leads nowhere useful. Added to api.js, already loaded on
# every page, so this works everywhere with no per-page changes.

set -e

if grep -q "macdenHideAnnouncementLink" portal/assets/api.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat >> portal/assets/api.js << 'ENGINE_EOF'

// ---- Hide the Announcement sidebar link for non-admins ----
// Regular staff can't post/manage announcements, so there's nothing
// useful behind this link for them -- hide it entirely rather than
// showing a dead end.
(async function macdenHideAnnouncementLink(){
  const link = document.querySelector('a[href="announcement.html"]');
  if (!link) return;

  try {
    const result = await apiRequest('/dashboard-check');
    if (result.staff.role !== 'admin') {
      link.style.display = 'none';
    }
  } catch (err) {
    // Not logged in / check failed -- leave it as-is
  }
})();
ENGINE_EOF

echo "    Added Announcement link admin-only visibility to portal/assets/api.js."
echo ""
echo "Done. Push with your usual save-progress.sh."
