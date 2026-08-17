#!/bin/bash
# fix-announcements-viewall-link-v1.sh
#
# Points the Announcements card's "View all" link to the real Broadcasts
# page instead of the dummy "#" placeholder.

set -e

if grep -q '<h2>Announcements</h2>' portal/dashboard.html && grep -A1 '<h2>Announcements</h2>' portal/dashboard.html | grep -q 'href="broadcasts.html"'; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-viewall.js << 'NODE_EOF'
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

const filePath = 'portal/dashboard.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

const anchor = `<h2>Announcements</h2>
              <a href="#">View all</a>`;
const replacement = `<h2>Announcements</h2>
              <a href="broadcasts.html">View all</a>`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the Announcements View all link in dashboard.html.');
  process.exit(1);
}
content = content.replace(anchor, replacement);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (View all now links to broadcasts.html).');
NODE_EOF

node .tmp-patch-viewall.js
rm .tmp-patch-viewall.js

echo ""
echo "Done. Push with your usual save-progress.sh."
