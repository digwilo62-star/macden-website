#!/bin/bash
# fix-live-updates-dashboard-v1.sh
#
# Dashboard listens for the shared 'macden:newActivity' event and
# refreshes the Announcements card automatically when it fires --
# reuses the existing renderAnnouncements() function, no new fetch logic.
# Requires fix-live-updates-engine-v1.sh to be applied first.

set -e

if grep -q "macden:newActivity" portal/dashboard.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-dashlive.js << 'NODE_EOF'
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

const anchor = `    init();`;
const listener = `    window.addEventListener('macden:newActivity', () => {
      apiRequest('/messages/announcements/active')
        .then(result => renderAnnouncements(result.announcements || []))
        .catch(() => {});
    });

    init();`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the init() call in dashboard.html.');
  process.exit(1);
}
content = content.replace(anchor, listener);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (live-refreshes announcements on new activity).');
NODE_EOF

node .tmp-patch-dashlive.js
rm .tmp-patch-dashlive.js

echo ""
echo "Done. Push with your usual save-progress.sh."
