#!/bin/bash
# fix-attendance-link-direct-nav-v1.sh
#
# Fixes the "opens a blank page, then reloads again" feeling when
# clicking Attendance in the sidebar. That happened because the link
# pointed to a small router page that checks your role, then redirects
# again -- two page loads stacked on top of each other instead of one.
#
# Now, since every page already checks who's logged in when it loads,
# that same check quietly fixes the Attendance link's actual destination
# before you ever click it -- so it becomes one direct jump to the right
# page, exactly like every other sidebar link. Added to api.js, which
# every portal page already loads, so this works everywhere with no
# per-page changes needed.

set -e

if grep -q "macdenFixAttendanceLink" portal/assets/api.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat >> portal/assets/api.js << 'ENGINE_EOF'

// ---- Point the sidebar's Attendance link straight at the right page ----
// Runs on every portal page load. Rewrites the link's destination based
// on role (admin -> full report, everyone else -> personal history)
// before it's ever clicked, so it's one direct navigation like any other
// sidebar link -- not a page that loads just to redirect again.
(async function macdenFixAttendanceLink(){
  const link = document.querySelector('a[href="attendance.html"]');
  if (!link) return; // this page has no sidebar, or no Attendance link -- nothing to do

  try {
    const result = await apiRequest('/dashboard-check');
    link.href = result.staff.role === 'admin' ? 'attendance-report.html' : 'my-attendance.html';
  } catch (err) {
    // Not logged in / check failed -- leave the link as-is, the router
    // page it points to still works correctly as a fallback
  }
})();
ENGINE_EOF

echo "    Added Attendance link auto-fix to portal/assets/api.js."
echo ""
echo "Done. Push with your usual save-progress.sh."
