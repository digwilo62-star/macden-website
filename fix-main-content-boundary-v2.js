// fix-main-content-boundary-v2.js
//
// CORRECTED APPROACH after the first version was proven wrong by
// directly inspecting the real browser DOM (not just counting text) --
// relocating a closing </div> through complex nested divs was
// unreliable. This instead finds #main-content's TRUE closing tag by
// properly counting nesting depth (not a regex guess), then moves the
// page's own <script> tags to sit just before it -- leaving every
// other div completely untouched in its original position.

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

// Finds the index right after the TRUE closing </div> for the div that
// starts at openTagEndIdx, by properly counting nested opens/closes --
// not a text-pattern guess.
function findMatchingCloseDiv(content, openTagEndIdx) {
  let depth = 1;
  const tagRegex = /<div[\s>]|<\/div>/g;
  tagRegex.lastIndex = openTagEndIdx;
  let m;
  while ((m = tagRegex.exec(content)) !== null) {
    if (m[0].startsWith('<div')) depth++;
    else depth--;
    if (depth === 0) return m.index;
  }
  return -1;
}

let fixed = [], alreadyDone = [], notFound = [], missingFile = [];

for (const page of PAGES) {
  const filePath = path.join('portal', page);
  if (!fs.existsSync(filePath)) { missingFile.push(page); continue; }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const mcIdx = content.indexOf('id="main-content"');
  if (mcIdx === -1) { notFound.push(page); continue; }

  const openTagEnd = content.indexOf('>', mcIdx) + 1;
  const closeDivIdx = findMatchingCloseDiv(content, openTagEnd);
  if (closeDivIdx === -1) { notFound.push(page); continue; }

  // Is the FIRST script tag already before this closing div? If so,
  // scripts are already correctly inside -- nothing to do.
  const firstScriptIdx = content.indexOf('<script', openTagEnd);
  if (firstScriptIdx === -1 || firstScriptIdx < closeDivIdx) {
    alreadyDone.push(page);
    continue;
  }

  // Find the end of the LAST </script> tag (scripts run from the first
  // <script right up to end of body, so grab everything to </body>)
  const bodyCloseIdx = content.indexOf('</body>');
  if (bodyCloseIdx === -1) { notFound.push(page); continue; }

  const scriptsBlock = content.slice(firstScriptIdx, bodyCloseIdx).trim();

  // Remove the scripts from their current (too-late) position, then
  // insert them right before the TRUE closing </div>
  const withoutScripts = content.slice(0, firstScriptIdx) + content.slice(bodyCloseIdx);
  const newCloseDivIdx = withoutScripts.indexOf('id="main-content"');
  const newOpenTagEnd = withoutScripts.indexOf('>', newCloseDivIdx) + 1;
  const newCloseDivPos = findMatchingCloseDiv(withoutScripts, newOpenTagEnd);

  const finalContent = withoutScripts.slice(0, newCloseDivPos) +
    '\n  ' + scriptsBlock + '\n  ' +
    withoutScripts.slice(newCloseDivPos);

  writeRestoringLineEndings(filePath, finalContent, usesCRLF);
  fixed.push(page);
}

console.log('Fixed (' + fixed.length + '):');
fixed.forEach(p => console.log('  ' + p));
if (alreadyDone.length) { console.log('\nAlready correct, skipped (' + alreadyDone.length + '):'); alreadyDone.forEach(p => console.log('  ' + p)); }
if (notFound.length) { console.log('\nCOULD NOT FIND expected structure (' + notFound.length + '):'); notFound.forEach(p => console.log('  ' + p)); }
if (missingFile.length) { console.log('\nFile not found (' + missingFile.length + '):'); missingFile.forEach(p => console.log('  ' + p)); }
