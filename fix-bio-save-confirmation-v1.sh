#!/bin/bash
# fix-bio-save-confirmation-v1.sh
#
# The Status/Bio save was never actually broken -- confirmed directly in
# the database that it was saving correctly the whole time. The real
# issue: no success confirmation ever showed, so a working save looked
# like nothing happened. Reuses the existing showAlert() success pattern
# already used elsewhere on this same page (password change).

set -e

if grep -q "showAlert(alertEl, 'Saved.', 'success')" portal/settings.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-bio.js << 'NODE_EOF'
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

const filePath = 'portal/settings.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

const oldHandler = `    document.getElementById('saveBioBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('profileAlert');
      hideAlert(alertEl);
      try {
        await apiRequest('/settings/profile', { method: 'PUT', body: { bio: document.getElementById('bioInput').value.trim() } });
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    });`;

const newHandler = `    document.getElementById('saveBioBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('profileAlert');
      hideAlert(alertEl);
      try {
        await apiRequest('/settings/profile', { method: 'PUT', body: { bio: document.getElementById('bioInput').value.trim() } });
        showAlert(alertEl, 'Saved.', 'success');
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    });`;

if (!content.includes(oldHandler)) {
  console.error('ERROR: could not find the saveBioBtn click handler in settings.html.');
  process.exit(1);
}
content = content.replace(oldHandler, newHandler);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/settings.html (bio save now shows a confirmation).');
NODE_EOF

node .tmp-patch-bio.js
rm .tmp-patch-bio.js

echo ""
echo "Done. Push with your usual save-progress.sh."
