#!/bin/bash
# fix-announcements-retire-broadcasts-v1.sh
#
# Final stage: retires the old Broadcasts page safely (redirects to the
# new Announcement page instead of deleting -- nothing breaks if an old
# link or bookmark points to it, and every already-sent broadcast stays
# exactly where it is in Inbox, completely untouched).
#
# Run AFTER fix-sidebar-rename-announcement-v1.sh and
# fix-sidebar-announcement-adminonly-v1.sh.

set -e

echo "==> Replacing portal/broadcasts.html with a redirect to announcement.html"
mkdir -p portal
cat > portal/broadcasts.html << 'REDIRECT_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Redirecting… — MACDEN Portal</title>
</head>
<body>
  <script>
    // Broadcasts has been replaced by the new Announcement system.
    // Redirecting anyone who lands here (an old bookmark, a stale
    // link) to the right place instead of a dead page.
    window.location.replace('announcement.html');
  </script>
</body>
</html>
REDIRECT_EOF

echo ""
echo "Done. The Announcement system is now fully live. Push with your usual save-progress.sh."
