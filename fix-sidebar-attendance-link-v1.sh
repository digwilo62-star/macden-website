#!/bin/bash
# fix-sidebar-attendance-link-v1.sh
#
# Adds "Attendance" to the sidebar across every portal page that has one.
# Links to portal/attendance.html -- a small router that sends admins to
# the full report and everyone else to their own personal history, so
# the same single sidebar link works correctly for everyone.
#
# Runs across each page independently and reports success/failure per
# file, rather than stopping at the first one that doesn't match --
# sidebars have drifted slightly between pages over tonight's work, so
# this is built to handle that safely rather than assume uniformity.

set -e

echo "==> Creating portal/attendance.html (role-aware router)"
mkdir -p portal
cat > portal/attendance.html << 'ROUTER_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Attendance — MACDEN Portal</title>
</head>
<body>
  <script src="assets/api.js"></script>
  <script>
    // Single sidebar link works for everyone -- this just sends each
    // person to the page that's actually meant for their role, so a
    // regular staff member never lands on the admin-only report.
    (async () => {
      try {
        const result = await apiRequest('/dashboard-check');
        window.location.replace(result.staff.role === 'admin' ? 'attendance-report.html' : 'my-attendance.html');
      } catch (err) {
        window.location.replace('login.html');
      }
    })();
  </script>
</body>
</html>

ROUTER_EOF

cat > .tmp-patch-sidebar.js << 'NODE_EOF'
const fs = require('fs');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

// Pages that have a normal, persistent portal sidebar. Excludes standalone
// pages (login, register, onboard, verify, the kiosk display, the
// printable ID card view) which have no sidebar to patch.
const pages = [
  'portal/admin-dashboard.html', 'portal/attendance-report.html', 'portal/broadcasts.html',
  'portal/compose.html', 'portal/dashboard.html', 'portal/directory.html',
  'portal/documents.html', 'portal/field-staff.html', 'portal/help.html',
  'portal/id-card-requests.html', 'portal/inbox.html', 'portal/leave.html',
  'portal/manage-staff.html', 'portal/my-attendance.html', 'portal/orgchart.html',
  'portal/pending-registrations.html', 'portal/policies.html', 'portal/prices.html',
  'portal/prices-history.html', 'portal/settings.html'
];

const newLink = `        <a href="attendance.html" class="sidebar-link"><i class="ti ti-clock"></i> Attendance</a>\n`;

let patched = [];
let alreadyDone = [];
let notFound = [];
let missingFile = [];

for (const filePath of pages) {
  if (!fs.existsSync(filePath)) {
    missingFile.push(filePath);
    continue;
  }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  if (content.includes('href="attendance.html"') || content.includes('> Attendance</a>')) {
    alreadyDone.push(filePath);
    continue;
  }

  // Insert right before the Settings link -- present on every page with
  // the standard sidebar, making it a reliable, low-risk anchor point
  // even where other links vary between pages.
  const settingsAnchor = '<a href="settings.html" class="sidebar-link"';
  const idx = content.indexOf(settingsAnchor);

  if (idx === -1) {
    notFound.push(filePath);
    continue;
  }

  // Find the start of that line to insert cleanly before it
  const lineStart = content.lastIndexOf('\n', idx) + 1;
  content = content.slice(0, lineStart) + newLink + content.slice(lineStart);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  patched.push(filePath);
}

console.log('');
console.log('Patched (' + patched.length + '):');
patched.forEach(p => console.log('  ' + p));

if (alreadyDone.length) {
  console.log('');
  console.log('Already had it, skipped (' + alreadyDone.length + '):');
  alreadyDone.forEach(p => console.log('  ' + p));
}

if (notFound.length) {
  console.log('');
  console.log('COULD NOT PATCH -- sidebar structure did not match (' + notFound.length + '):');
  notFound.forEach(p => console.log('  ' + p));
  console.log('  (these need a look individually -- their sidebar differs from the standard one)');
}

if (missingFile.length) {
  console.log('');
  console.log('File not found, skipped (' + missingFile.length + '):');
  missingFile.forEach(p => console.log('  ' + p));
}
NODE_EOF

node .tmp-patch-sidebar.js
rm .tmp-patch-sidebar.js

echo ""
echo "Done. Push with your usual save-progress.sh."
