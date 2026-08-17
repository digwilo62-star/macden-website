#!/bin/bash
# fix-attendance-pages-full-sidebar-v1.sh
#
# attendance-report.html and my-attendance.html were both built with
# their own shorter, separate sidebar (Dashboard/Directory/Settings only)
# rather than the real full one every other page has. Replaces both
# with the complete, correct sidebar -- matching dashboard.html exactly,
# with Attendance included and marked active on whichever page you're on.

set -e

cat > .tmp-patch-fullsidebar.js << 'NODE_EOF'
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

function fullSidebar(activeHref) {
  const items = [
    ['dashboard.html', 'ti-layout-dashboard', 'Dashboard'],
    ['inbox.html', 'ti-mail', 'Inbox'],
    ['compose.html', 'ti-pencil', 'Compose'],
    ['broadcasts.html', 'ti-speakerphone', 'Broadcasts'],
    ['directory.html', 'ti-users', 'Directory'],
    ['attendance.html', 'ti-clock', 'Attendance'],
    ['leave.html', 'ti-calendar-event', 'Leave &amp; Requests'],
    ['documents.html', 'ti-file-text', 'Documents'],
    ['policies.html', 'ti-book', 'Policies'],
    ['settings.html', 'ti-settings', 'Settings']
  ];
  return items.map(([href, icon, label]) => {
    const isActive = href === activeHref;
    return `        <a href="${href}" class="sidebar-link${isActive ? ' active' : ''}"><i class="ti ${icon}"></i> ${label}</a>`;
  }).join('\n');
}

const targets = [
  { file: 'portal/attendance-report.html', activeHref: 'attendance.html' },
  { file: 'portal/my-attendance.html', activeHref: 'attendance.html' }
];

for (const { file, activeHref } of targets) {
  if (!fs.existsSync(file)) {
    console.log('    SKIPPED (not found): ' + file);
    continue;
  }

  let { normalized: content, usesCRLF } = readNormalized(file);

  const navStart = content.indexOf('<nav class="sidebar-nav">');
  const navEnd = content.indexOf('</nav>', navStart);

  if (navStart === -1 || navEnd === -1) {
    console.log('    COULD NOT FIND sidebar-nav block in: ' + file);
    continue;
  }

  const before = content.slice(0, navStart + '<nav class="sidebar-nav">'.length);
  const after = content.slice(navEnd);
  const newContent = before + '\n' + fullSidebar(activeHref) + '\n      ' + after;

  writeRestoringLineEndings(file, newContent, usesCRLF);
  console.log('    Patched: ' + file + ' (full sidebar, "' + activeHref + '" marked active)');
}
NODE_EOF

node .tmp-patch-fullsidebar.js
rm .tmp-patch-fullsidebar.js

echo ""
echo "Done. Push with your usual save-progress.sh."
