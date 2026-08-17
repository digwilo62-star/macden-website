
#!/bin/bash
# fix-bio-save-autohide-v1.sh
#
# The "Saved." confirmation was staying on screen permanently instead of
# behaving like a brief confirmation. Now auto-hides after 3 seconds.
#
# Note: the password-change success message has this exact same
# limitation (stays forever) -- this only fixes the bio save specifically,
# since that's what was reported. Let me know if you want the same
# auto-hide added to the password success message too.

set -e

if grep -q "setTimeout(() => hideAlert(alertEl), 3000)" portal/settings.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-bioautohide.js << 'NODE_EOF'
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
        showAlert(alertEl, 'Saved.', 'success');
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
        setTimeout(() => hideAlert(alertEl), 3000);
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
console.log('    Patched portal/settings.html (Saved confirmation now auto-hides after 3 seconds).');
NODE_EOF

node .tmp-patch-bioautohide.js
rm .tmp-patch-bioautohide.js

echo ""
echo "Done. Push with your usual save-progress.sh."
