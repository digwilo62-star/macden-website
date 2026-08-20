// check-collisions.js
//
// Scans every real portal page's own inline <script> block, extracts
// top-level (not nested inside a function) const/let/class/function
// declarations, and cross-checks all pages against each other for any
// name used in more than one file -- these would collide under boosted
// navigation, since the JS scope persists between page swaps instead of
// resetting like a normal page load.

const fs = require('fs');
const path = require('path');

const PAGES_TO_CHECK = [
  'admin-dashboard.html', 'announcement.html', 'attendance-report.html',
  'compose.html', 'dashboard.html', 'directory.html', 'documents.html',
  'field-staff.html', 'help.html', 'inbox.html', 'leave.html',
  'manage-staff.html', 'my-attendance.html', 'orgchart.html',
  'pending-registrations.html', 'policies.html', 'settings.html'
];

function extractLastInlineScript(html) {
  const matches = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  return matches.length ? matches[matches.length - 1][1] : null;
}

// Finds declarations that are NOT indented beyond the script's own base
// indentation -- i.e. genuinely top-level, not nested inside a function
// or block. Uses the minimum indentation found on any non-blank line as
// the baseline, since scripts are indented differently across files.
function findTopLevelDeclarations(scriptContent) {
  const lines = scriptContent.split('\n');
  const nonBlank = lines.filter(l => l.trim().length > 0);
  if (nonBlank.length === 0) return [];

  const indents = nonBlank.map(l => l.match(/^(\s*)/)[1].length);
  const baseIndent = Math.min(...indents);

  const declarations = [];
  const declRegex = /^(?:async\s+)?(?:function\s+(\w+)|const\s+(\w+)|let\s+(\w+)|class\s+(\w+))/;

  for (const line of lines) {
    const indent = line.match(/^(\s*)/)[1].length;
    if (line.trim().length === 0) continue;
    if (indent > baseIndent) continue; // nested inside something, skip

    const m = line.trim().match(declRegex);
    if (m) {
      const name = m[1] || m[2] || m[3] || m[4];
      declarations.push(name);
    }
  }
  return declarations;
}

const declarationsByFile = {};

for (const page of PAGES_TO_CHECK) {
  const filePath = path.join('portal', page);
  if (!fs.existsSync(filePath)) continue;

  const html = fs.readFileSync(filePath, 'utf8');
  const script = extractLastInlineScript(html);
  if (!script) continue;

  declarationsByFile[page] = findTopLevelDeclarations(script);
}

console.log('=== Top-level declarations found per page ===\n');
for (const [page, decls] of Object.entries(declarationsByFile)) {
  console.log(page + ':');
  console.log('  ' + (decls.length ? decls.join(', ') : '(none found)'));
}

console.log('\n=== Checking for collisions across pages ===\n');
const nameToFiles = {};
for (const [page, decls] of Object.entries(declarationsByFile)) {
  for (const name of decls) {
    (nameToFiles[name] = nameToFiles[name] || []).push(page);
  }
}

let foundCollision = false;
for (const [name, files] of Object.entries(nameToFiles)) {
  const uniqueFiles = [...new Set(files)];
  if (uniqueFiles.length > 1) {
    foundCollision = true;
    console.log('COLLISION: "' + name + '" declared in ' + uniqueFiles.length + ' files:');
    uniqueFiles.forEach(f => console.log('  ' + f));
  }
}

if (!foundCollision) {
  console.log('No collisions found across ' + Object.keys(declarationsByFile).length + ' pages checked.');
}
