// build-sidebar.js
//
// The ONE real source of truth for the sidebar. Edit the SIDEBAR_ITEMS
// list below, then run this script -- it regenerates the sidebar inside
// every portal page automatically. This is the actual fix for tonight's
// repeated problem: the sidebar was copied into ~20 separate files that
// could each drift independently. Now there's exactly one place to edit.
//
// Run this every time the sidebar needs to change, same as any other
// fix-*.sh script -- then verify-before-push.sh, then push.

const fs = require('fs');
const path = require('path');

const SIDEBAR_ITEMS = [
  { href: 'dashboard.html', icon: 'ti-layout-dashboard', label: 'Dashboard' },
  { href: 'inbox.html', icon: 'ti-mail', label: 'Inbox', extra: ' <span class="badge" id="unreadBadge" style="display:none;">0</span>' },
  { href: 'compose.html', icon: 'ti-pencil', label: 'Compose' },
  { href: 'announcement.html', icon: 'ti-speakerphone', label: 'Announcement' },
  { href: 'directory.html', icon: 'ti-users', label: 'Directory' },
  { href: 'attendance.html', icon: 'ti-clock', label: 'Attendance' },
  { href: 'leave.html', icon: 'ti-calendar-event', label: 'Leave &amp; Requests' },
  { href: 'documents.html', icon: 'ti-file-text', label: 'Documents' },
  { href: 'policies.html', icon: 'ti-book', label: 'Policies' },
  { href: 'settings.html', icon: 'ti-settings', label: 'Settings' },
];

// Pages that have a sidebar at all. Standalone pages (login, register,
// onboard, verify, the kiosk display, the printable ID card) don't.
const PAGES_WITH_SIDEBAR = [
  'admin-dashboard.html', 'announcement.html', 'attendance-report.html',
  'broadcasts.html', 'compose.html', 'dashboard.html', 'directory.html',
  'documents.html', 'field-staff.html', 'help.html', 'id-card-requests.html',
  'inbox.html', 'leave.html', 'manage-staff.html', 'my-attendance.html',
  'orgchart.html', 'pending-registrations.html', 'policies.html', 'prices.html',
  'prices-history.html', 'settings.html'
];

function renderSidebarNav(currentPage) {
  const links = SIDEBAR_ITEMS.map(item => {
    const isActive = item.href === currentPage;
    const extra = item.extra || '';
    return `        <a href="${item.href}" class="sidebar-link${isActive ? ' active' : ''}"><i class="ti ${item.icon}"></i> ${item.label}${extra}</a>`;
  }).join('\n');

  return `      <nav class="sidebar-nav">\n${links}\n      </nav>\n      <div class="sidebar-logout">\n        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>\n        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>\n      </div>`;
}

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

const START_MARKER = '<!-- SIDEBAR:START -->';
const END_MARKER = '<!-- SIDEBAR:END -->';

let built = [], missingMarker = [], missingFile = [];

for (const page of PAGES_WITH_SIDEBAR) {
  const filePath = path.join('portal', page);
  if (!fs.existsSync(filePath)) { missingFile.push(page); continue; }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const startIdx = content.indexOf(START_MARKER);
  const endIdx = content.indexOf(END_MARKER);

  if (startIdx === -1 || endIdx === -1) {
    missingMarker.push(page);
    continue;
  }

  const before = content.slice(0, startIdx + START_MARKER.length);
  const after = content.slice(endIdx);
  const newContent = before + '\n' + renderSidebarNav(page) + '\n      ' + after;

  writeRestoringLineEndings(filePath, newContent, usesCRLF);
  built.push(page);
}

console.log('Built (' + built.length + '):');
built.forEach(p => console.log('  ' + p));
if (missingMarker.length) {
  console.log('\nNo SIDEBAR:START/END markers found (' + missingMarker.length + '):');
  missingMarker.forEach(p => console.log('  ' + p));
  console.log('  (these need the markers added once -- see the migration script)');
}
if (missingFile.length) {
  console.log('\nFile not found, skipped (' + missingFile.length + '):');
  missingFile.forEach(p => console.log('  ' + p));
}
