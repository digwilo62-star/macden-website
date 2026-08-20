// add-main-content-id.js
//
// Adds id="main-content" alongside the existing class="main-content" on
// every real page -- this is what tells htmx exactly what to swap
// during boosted navigation, leaving the sidebar untouched. The
// existing class is left completely intact, so nothing currently
// depending on it for styling is affected.

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

  if (content.includes('id="main-content"')) { alreadyDone.push(page); continue; }

  const oldTag = '<div class="main-content">';
  const newTag = '<div class="main-content" id="main-content">';

  if (!content.includes(oldTag)) { notFound.push(page); continue; }

  content = content.replace(oldTag, newTag);
  writeRestoringLineEndings(filePath, content, usesCRLF);
  updated.push(page);
}

console.log('Updated (' + updated.length + '):');
updated.forEach(p => console.log('  ' + p));
if (alreadyDone.length) { console.log('\nAlready had it (' + alreadyDone.length + '):'); alreadyDone.forEach(p => console.log('  ' + p)); }
if (notFound.length) { console.log('\nCOULD NOT FIND class="main-content" (' + notFound.length + '):'); notFound.forEach(p => console.log('  ' + p)); console.log('  (worth a manual look -- this page may be structured differently)'); }
if (missingFile.length) { console.log('\nFile not found (' + missingFile.length + '):'); missingFile.forEach(p => console.log('  ' + p)); }
