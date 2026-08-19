#!/bin/bash
# migrate-sidebar-to-markers-v1.sh
#
# ONE-TIME migration: replaces each page's existing hardcoded sidebar
# with SIDEBAR:START/END markers, then immediately runs build-sidebar.js
# to fill them back in with the correct, freshly-generated version --
# so no page ever sits with a broken/empty sidebar in between.
#
# After this runs once, you never touch individual pages' sidebars again --
# edit build-sidebar.js's SIDEBAR_ITEMS list, then just run build-sidebar.js.
#
# Runs across each page independently and reports success/failure per
# file, same resilient approach used for every multi-page rollout tonight.

set -e

cat > .tmp-migrate-sidebar.js << 'NODE_EOF'
const fs = require('fs');
const path = require('path');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

const PAGES_WITH_SIDEBAR = [
  'admin-dashboard.html', 'announcement.html', 'attendance-report.html',
  'broadcasts.html', 'compose.html', 'dashboard.html', 'directory.html',
  'documents.html', 'field-staff.html', 'help.html', 'id-card-requests.html',
  'inbox.html', 'leave.html', 'manage-staff.html', 'my-attendance.html',
  'orgchart.html', 'pending-registrations.html', 'policies.html', 'prices.html',
  'prices-history.html', 'settings.html'
];

let migrated = [], alreadyDone = [], notFound = [], missingFile = [];

for (const page of PAGES_WITH_SIDEBAR) {
  const filePath = path.join('portal', page);
  if (!fs.existsSync(filePath)) { missingFile.push(page); continue; }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  if (content.includes('SIDEBAR:START')) { alreadyDone.push(page); continue; }

  const navStart = content.indexOf('<nav class="sidebar-nav">');
  if (navStart === -1) { notFound.push(page); continue; }

  // Find the real end: prefer the closing sidebar-logout div if present,
  // otherwise fall back to just the nav's own closing tag
  const logoutStart = content.indexOf('<div class="sidebar-logout">', navStart);
  let blockEnd;
  if (logoutStart !== -1) {
    const logoutDivEnd = content.indexOf('</div>', logoutStart);
    blockEnd = logoutDivEnd + '</div>'.length;
  } else {
    const navEnd = content.indexOf('</nav>', navStart);
    if (navEnd === -1) { notFound.push(page); continue; }
    blockEnd = navEnd + '</nav>'.length;
  }

  const before = content.slice(0, navStart);
  const after = content.slice(blockEnd);
  const newContent = before + '<!-- SIDEBAR:START -->\n      <!-- SIDEBAR:END -->' + after;

  writeRestoringLineEndings(filePath, newContent, usesCRLF);
  migrated.push(page);
}

console.log('Migrated to markers (' + migrated.length + '):');
migrated.forEach(p => console.log('  ' + p));
if (alreadyDone.length) { console.log('\nAlready migrated, skipped (' + alreadyDone.length + '):'); alreadyDone.forEach(p => console.log('  ' + p)); }
if (notFound.length) { console.log('\nCOULD NOT FIND a sidebar to migrate (' + notFound.length + '):'); notFound.forEach(p => console.log('  ' + p)); console.log('  (worth a manual look -- this page may need the markers added by hand)'); }
if (missingFile.length) { console.log('\nFile not found (' + missingFile.length + '):'); missingFile.forEach(p => console.log('  ' + p)); }
NODE_EOF

echo "==> Step 1: converting existing hardcoded sidebars to markers"
node .tmp-migrate-sidebar.js
rm .tmp-migrate-sidebar.js

echo ""
echo "==> Step 2: running the first real build to fill markers back in"
node build-sidebar.js

echo ""
echo "Done. Push with your usual save-progress.sh."
