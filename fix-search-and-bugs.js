// Wires up company-wide search across every portal page, and fixes a real
// bug (broken logout icon: "titi-logout" missing a space). Edits your REAL
// files in place -- run this from your repo root.
//
//   node fix-search-and-bugs.js

const fs = require('fs');
const path = require('path');

const accountingDir = path.join(__dirname, 'accounting');
const pagesToSkip = ['login.html']; // no topbar on the login page

const files = fs.readdirSync(accountingDir).filter(f =>
  f.endsWith('.html') && !pagesToSkip.includes(f)
);

const oldSearchBar = '<div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>';
const newSearchBar = '<div class="topbar-search"><input type="text" id="globalSearchInput" placeholder="Search messages, people, documents…"><div class="search-dropdown" id="globalSearchDropdown"></div></div>';

let patchedCount = 0;
let bugFixCount = 0;
let skippedCount = 0;

files.forEach(file => {
  const filePath = path.join(accountingDir, file);
  let content = fs.readFileSync(filePath, 'utf8');
  let changed = false;

  // 1. Wire up the search bar
  if (content.includes(oldSearchBar)) {
    content = content.replace(oldSearchBar, newSearchBar);
    changed = true;
  } else if (content.includes('id="globalSearchInput"')) {
    console.log(file + ': search bar already wired, skipping that part.');
  } else {
    console.log(file + ': WARNING - search bar markup not found in expected format, skipped.');
  }

  // 2. Add search.css link (right after portal-shell.css)
  if (!content.includes('assets/search.css')) {
    content = content.replace(
      '<link rel="stylesheet" href="assets/portal-shell.css">',
      '<link rel="stylesheet" href="assets/portal-shell.css">\n  <link rel="stylesheet" href="assets/search.css">'
    );
    changed = true;
  }

  // 3. Add search.js script tag (right after notifications.js, or api.js if notifications.js isn't present)
  if (!content.includes('assets/search.js')) {
    if (content.includes('<script src="assets/notifications.js"></script>')) {
      content = content.replace(
        '<script src="assets/notifications.js"></script>',
        '<script src="assets/notifications.js"></script>\n  <script src="assets/search.js"></script>'
      );
    } else {
      content = content.replace(
        '<script src="assets/api.js"></script>',
        '<script src="assets/api.js"></script>\n  <script src="assets/search.js"></script>'
      );
    }
    changed = true;
  }

  // 4. Fix the broken logout icon bug (missing space: "titi-logout")
  if (content.includes('class="titi-logout"')) {
    content = content.replace(/class="titi-logout"/g, 'class="ti ti-logout"');
    changed = true;
    bugFixCount++;
  }

  if (changed) {
    fs.writeFileSync(filePath, content, 'utf8');
    patchedCount++;
    console.log(file + ': patched.');
  } else {
    skippedCount++;
  }
});

console.log('\n' + patchedCount + ' file(s) patched, ' + bugFixCount + ' logout-icon bug(s) fixed, ' + skippedCount + ' already up to date.');

