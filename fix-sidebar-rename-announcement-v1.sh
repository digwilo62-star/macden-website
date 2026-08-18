#!/bin/bash
# fix-sidebar-rename-announcement-v1.sh
#
# Renames "Broadcasts" to "Announcement" in the sidebar across every
# page that has it, and points it at the new announcement.html instead
# of the old broadcasts.html. Runs across each page independently and
# reports success/failure per file, same resilient approach used for
# the earlier Attendance rollout.

set -e

cat > .tmp-patch-rename.js << 'NODE_EOF'
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

const pages = [
  'portal/admin-dashboard.html', 'portal/attendance-report.html', 'portal/compose.html',
  'portal/dashboard.html', 'portal/directory.html', 'portal/documents.html',
  'portal/field-staff.html', 'portal/help.html', 'portal/id-card-requests.html',
  'portal/inbox.html', 'portal/leave.html', 'portal/manage-staff.html',
  'portal/my-attendance.html', 'portal/orgchart.html', 'portal/pending-registrations.html',
  'portal/policies.html', 'portal/prices.html', 'portal/prices-history.html',
  'portal/settings.html'
];

const oldLink = `<a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>`;
const newLink = `<a href="announcement.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Announcement</a>`;
const oldLinkActive = `<a href="broadcasts.html" class="sidebar-link active"><i class="ti ti-speakerphone"></i> Broadcasts</a>`;
const newLinkActive = `<a href="announcement.html" class="sidebar-link active"><i class="ti ti-speakerphone"></i> Announcement</a>`;

let renamed = [], alreadyDone = [], notFound = [], missingFile = [];

for (const filePath of pages) {
  if (!fs.existsSync(filePath)) { missingFile.push(filePath); continue; }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  if (content.includes('href="announcement.html"')) { alreadyDone.push(filePath); continue; }

  let changed = false;
  if (content.includes(oldLink)) { content = content.replace(oldLink, newLink); changed = true; }
  if (content.includes(oldLinkActive)) { content = content.replace(oldLinkActive, newLinkActive); changed = true; }

  if (!changed) { notFound.push(filePath); continue; }

  writeRestoringLineEndings(filePath, content, usesCRLF);
  renamed.push(filePath);
}

console.log('');
console.log('Renamed (' + renamed.length + '):');
renamed.forEach(p => console.log('  ' + p));
if (alreadyDone.length) { console.log(''); console.log('Already done, skipped (' + alreadyDone.length + '):'); alreadyDone.forEach(p => console.log('  ' + p)); }
if (notFound.length) { console.log(''); console.log('COULD NOT FIND the Broadcasts link (' + notFound.length + '):'); notFound.forEach(p => console.log('  ' + p)); console.log('  (this page may not have a Broadcasts link at all -- worth a quick look)'); }
if (missingFile.length) { console.log(''); console.log('File not found (' + missingFile.length + '):'); missingFile.forEach(p => console.log('  ' + p)); }
NODE_EOF

node .tmp-patch-rename.js
rm .tmp-patch-rename.js

echo ""
echo "Done. Push with your usual save-progress.sh."
