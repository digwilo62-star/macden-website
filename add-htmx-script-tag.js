// add-htmx-script-tag.js
//
// Adds the self-hosted htmx script tag to every real page's <head>,
// right alongside the existing stylesheet links.

const fs = require('fs');
const path = require('path');

const PAGES = [
  'admin-dashboard.html', 'announcement.html', 'attendance-report.html',
  'compose.html', 'dashboard.html', 'directory.html', 'documents.html',
  'field-staff.html', 'help.html', 'inbox.html', 'leave.html',
  'manage-staff.html', 'my-attendance.html', 'orgchart.html',
  'pending-registrations.html', 'policies.html', 'settings.html'
];

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

let updated = [], alreadyDone = [], notFound = [], missingFile = [];

for (const page of PAGES) {
  const filePath = path.join('portal', page);
  if (!fs.existsSync(filePath)) { missingFile.push(page); continue; }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  if (content.includes('assets/htmx.min.js')) { alreadyDone.push(page); continue; }

  const anchor = '<link rel="stylesheet" href="assets/portal-style.css">';
  if (!content.includes(anchor)) { notFound.push(page); continue; }

  content = content.replace(anchor, '<script src="assets/htmx.min.js"></script>\n  ' + anchor);
  writeRestoringLineEndings(filePath, content, usesCRLF);
  updated.push(page);
}

console.log('Updated (' + updated.length + '):');
updated.forEach(p => console.log('  ' + p));
if (alreadyDone.length) { console.log('\nAlready had it (' + alreadyDone.length + '):'); alreadyDone.forEach(p => console.log('  ' + p)); }
if (notFound.length) { console.log('\nCOULD NOT FIND the stylesheet anchor (' + notFound.length + '):'); notFound.forEach(p => console.log('  ' + p)); }
if (missingFile.length) { console.log('\nFile not found (' + missingFile.length + '):'); missingFile.forEach(p => console.log('  ' + p)); }
