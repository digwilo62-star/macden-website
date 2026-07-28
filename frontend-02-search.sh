#!/usr/bin/env bash
# FRONTEND: Company-wide search (#23), wiring the search bar that's been
# sitting in every topbar unwired since the rebuild started. Also fixes
# a real bug: the Logout icon was broken ('titi-logout' missing a space)
# on every page.
#
# This works differently from previous scripts -- instead of overwriting
# your files, it adds 2 new files, then runs a Node script that safely
# EDITS your existing pages in place (finds the exact search bar markup
# and wraps it, adds the new CSS/JS links, fixes the icon bug). Tested
# against your real dashboard.html content before being sent to you --
# and confirmed safe to run more than once if needed.
#
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p accounting/assets

cat > accounting/assets/search.css << 'EOF_ACCOUNTING_ASSETS_SEARCH_CSS'
/* ---------- Company-wide search dropdown ---------- */

.topbar-search { position: relative; }

.search-dropdown {
  display: none;
  position: absolute;
  top: calc(100% + 8px);
  left: 0;
  width: 420px;
  max-height: 440px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  box-shadow: 0 8px 24px rgba(0,0,0,0.12);
  z-index: 60;
  overflow-y: auto;
}

.search-dropdown.visible { display: block; }

.search-section { padding: 10px 0; border-bottom: 1px solid var(--border); }
.search-section:last-child { border-bottom: none; }

.search-section-label {
  padding: 4px 16px 8px;
  font-size: 10.5px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--text-muted);
}

.search-result-row {
  display: block;
  padding: 9px 16px;
  text-decoration: none;
  color: inherit;
  cursor: pointer;
}

.search-result-row:hover { background: var(--surface-raised); }

.search-result-title { font-size: 13px; font-weight: 600; color: var(--text-primary); }
.search-result-detail { font-size: 11.5px; color: var(--text-secondary); margin-top: 1px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.search-empty-state { padding: 24px 16px; text-align: center; color: var(--text-muted); font-size: 12.5px; }
.search-hint { padding: 24px 16px; text-align: center; color: var(--text-muted); font-size: 12px; }

EOF_ACCOUNTING_ASSETS_SEARCH_CSS

cat > accounting/assets/search.js << 'EOF_ACCOUNTING_ASSETS_SEARCH_JS'
// Company-wide search — wires up the search box that's been sitting in
// every topbar, unwired, since the portal rebuild started. Requires this
// markup around the input (added automatically by fix-search-and-bugs.js):
//   <div class="topbar-search">
//     <input type="text" id="globalSearchInput" placeholder="...">
//     <div class="search-dropdown" id="globalSearchDropdown"></div>
//   </div>

function initGlobalSearch() {
  const input = document.getElementById('globalSearchInput');
  const dropdown = document.getElementById('globalSearchDropdown');
  if (!input || !dropdown) return;

  let searchTimeout = null;

  input.addEventListener('input', () => {
    clearTimeout(searchTimeout);
    const q = input.value.trim();

    if (!q) {
      dropdown.classList.remove('visible');
      return;
    }
    if (q.length < 2) {
      dropdown.innerHTML = '<div class="search-hint">Keep typing…</div>';
      dropdown.classList.add('visible');
      return;
    }

    searchTimeout = setTimeout(() => runSearch(q), 300);
  });

  input.addEventListener('focus', () => {
    if (input.value.trim().length >= 2) dropdown.classList.add('visible');
  });

  document.addEventListener('click', (e) => {
    if (!e.target.closest('.topbar-search')) {
      dropdown.classList.remove('visible');
    }
  });

  async function runSearch(q) {
    dropdown.innerHTML = '<div class="search-hint">Searching…</div>';
    dropdown.classList.add('visible');

    try {
      const result = await apiRequest('/search?q=' + encodeURIComponent(q));
      const totalResults = result.messages.length + result.documents.length + result.policies.length;

      if (totalResults === 0) {
        dropdown.innerHTML = '<div class="search-empty-state">No results for "' + q + '"</div>';
        return;
      }

      let html = '';

      if (result.messages.length > 0) {
        html += '<div class="search-section"><div class="search-section-label">Messages</div>';
        html += result.messages.map(m =>
          '<a class="search-result-row" href="inbox.html?id=' + m.conversationId + '">' +
            '<div class="search-result-title">' + m.subject + '</div>' +
            (m.snippet ? '<div class="search-result-detail">' + m.snippet + '</div>' : '') +
          '</a>'
        ).join('');
        html += '</div>';
      }

      if (result.documents.length > 0) {
        html += '<div class="search-section"><div class="search-section-label">Documents</div>';
        html += result.documents.map(d =>
          '<a class="search-result-row" href="documents.html">' +
            '<div class="search-result-title">' + d.fileName + '</div>' +
            '<div class="search-result-detail">' + d.category + '</div>' +
          '</a>'
        ).join('');
        html += '</div>';
      }

      if (result.policies.length > 0) {
        html += '<div class="search-section"><div class="search-section-label">Policies</div>';
        html += result.policies.map(p =>
          '<a class="search-result-row" href="policies.html?id=' + p.id + '">' +
            '<div class="search-result-title">' + p.title + '</div>' +
            (p.snippet ? '<div class="search-result-detail">' + p.snippet + '</div>' : '') +
          '</a>'
        ).join('');
        html += '</div>';
      }

      dropdown.innerHTML = html;
    } catch (err) {
      dropdown.innerHTML = '<div class="search-empty-state">Search failed. Try again.</div>';
    }
  }
}

document.addEventListener('DOMContentLoaded', initGlobalSearch);

EOF_ACCOUNTING_ASSETS_SEARCH_JS

cat > fix-search-and-bugs.js << 'EOF_FIXER_JS'
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

EOF_FIXER_JS

echo "New search files created. Now running the patcher on your real pages..."
node fix-search-and-bugs.js
echo ""
echo "Done. Restart your server and test the search bar on any page."