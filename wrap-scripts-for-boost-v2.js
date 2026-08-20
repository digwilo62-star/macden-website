// wrap-scripts-for-boost.js
//
// Wraps each real page's own inline script in an IIFE, preventing the
// 11 confirmed real name collisions from crashing boosted navigation --
// while automatically re-exposing exactly the functions and variables
// each page's own onclick="" attributes actually need, so every
// existing button keeps working correctly.
//
// Functions get a simple one-time window.name = name (they don't
// change after being declared). Variables get a LIVE getter instead of
// a one-time copy -- confirmed necessary via research: a plain copy
// would freeze at its initial value and go stale the moment the real
// variable changes (e.g. currentConversationId updating as a user
// opens different messages), even though the onclick attribute would
// keep reading the old, frozen copy.

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

function findOnclickIdentifiers(html) {
  // Finds every "onclick=" occurrence and extracts identifier tokens
  // from a generous window of text right after it, rather than trying
  // to precisely find the attribute's closing quote -- real pages have
  // onclick attributes with nested, multi-layered quote escaping (JS
  // building HTML strings containing further escaped arguments) that
  // proved genuinely difficult to parse exactly, confirmed by two real
  // misses in testing (selectRecipient, closeLeaveDetail). A window
  // that runs slightly past the true boundary just catches a few extra
  // harmless tokens; a window that's too tight risks missing a real one.
  const WINDOW_SIZE = 200;
  const identifiers = new Set();
  const jsKeywords = new Set(['this', 'event', 'document', 'window', 'true', 'false', 'null', 'undefined', 'getElementById', 'classList', 'remove', 'add', 'focus', 'stopPropagation', 'textContent', 'div', 'class', 'button', 'span', 'style']);

  let searchFrom = 0;
  while (true) {
    const idx = html.indexOf('onclick=', searchFrom);
    if (idx === -1) break;
    const window = html.slice(idx, idx + WINDOW_SIZE);
    const tokens = window.match(/[A-Za-z_$][A-Za-z0-9_$]*/g) || [];
    for (const t of tokens) {
      if (!jsKeywords.has(t) && t !== 'onclick') identifiers.add(t);
    }
    searchFrom = idx + 'onclick='.length;
  }
  return identifiers;
}

function findTopLevelDeclarations(scriptContent) {
  const lines = scriptContent.split('\n');
  const nonBlank = lines.filter(l => l.trim().length > 0);
  if (nonBlank.length === 0) return { functions: [], variables: [] };

  const indents = nonBlank.map(l => l.match(/^(\s*)/)[1].length);
  const baseIndent = Math.min(...indents);

  const functions = [];
  const variables = [];

  for (const line of lines) {
    const indent = line.match(/^(\s*)/)[1].length;
    if (line.trim().length === 0 || indent > baseIndent) continue;

    const fnMatch = line.trim().match(/^(?:async\s+)?function\s+(\w+)/);
    if (fnMatch) { functions.push(fnMatch[1]); continue; }

    const varMatch = line.trim().match(/^(?:const|let)\s+(\w+)/);
    if (varMatch) { variables.push(varMatch[1]); continue; }
  }
  return { functions, variables };
}

let results = [];

for (const page of PAGES) {
  const filePath = path.join('portal', page);
  if (!fs.existsSync(filePath)) { results.push({ page, status: 'file not found' }); continue; }

  let { normalized: content, usesCRLF } = readNormalized(filePath);

  if (content.includes('/* BOOST-WRAPPED */')) {
    results.push({ page, status: 'already wrapped, skipped' });
    continue;
  }

  const scriptMatches = [...content.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  if (scriptMatches.length === 0) { results.push({ page, status: 'no inline script found' }); continue; }

  const lastMatch = scriptMatches[scriptMatches.length - 1];
  const scriptContent = lastMatch[1];

  const onclickIds = findOnclickIdentifiers(content);
  const { functions, variables } = findTopLevelDeclarations(scriptContent);

  const exposedFunctions = functions.filter(f => onclickIds.has(f));
  const exposedVariables = variables.filter(v => onclickIds.has(v));

  let exposureLines = '';
  if (exposedFunctions.length || exposedVariables.length) {
    exposureLines = '\n      // Re-exposed for onclick="" attributes on this page (auto-detected)\n';
    exposedFunctions.forEach(f => { exposureLines += `      window.${f} = ${f};\n`; });
    exposedVariables.forEach(v => { exposureLines += `      Object.defineProperty(window, '${v}', { get: () => ${v}, configurable: true });\n`; });
  }

  const wrapped = `\n    /* BOOST-WRAPPED */\n    (function(){\n${scriptContent}${exposureLines}    })();\n  `;

  const newContent = content.slice(0, lastMatch.index) +
    '<script>' + wrapped + '</script>' +
    content.slice(lastMatch.index + lastMatch[0].length);

  writeRestoringLineEndings(filePath, newContent, usesCRLF);
  results.push({ page, status: 'wrapped', exposedFunctions, exposedVariables });
}

console.log('=== Results ===\n');
for (const r of results) {
  console.log(r.page + ': ' + r.status);
  if (r.exposedFunctions && r.exposedFunctions.length) console.log('  functions re-exposed: ' + r.exposedFunctions.join(', '));
  if (r.exposedVariables && r.exposedVariables.length) console.log('  variables re-exposed (live): ' + r.exposedVariables.join(', '));
}
