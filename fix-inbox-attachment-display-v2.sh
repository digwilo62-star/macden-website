#!/bin/bash
# fix-inbox-attachment-display-v1.sh
#
# Attachments now show like a real file manager entry: the actual
# original filename (extracted from the storage URL, since it's
# preserved there), with a proper colored file-type icon -- green for
# Excel, red for PDF -- instead of generic "Download attachment" text.
#
# Word/.docx isn't currently an accepted upload type (the upload filter
# only allows PDF and .xlsx) -- this only affects display, not upload,
# so nothing changes there. Ask separately if Word support should be added.

set -e

if grep -q "attachmentDisplayName" portal/inbox.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-attach.js << 'NODE_EOF'
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

const filePath = 'portal/inbox.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

// 1. Replace the generic attachment link with a proper file-manager-style entry
const oldLine = `            attachmentHtml = '<a href="' + m.attachment_url + '" target="_blank" rel="noopener" class="email-attachment"><i class="ti ' + icon + '"></i> Download attachment</a>';`;

const newLine = `            const fileName = attachmentDisplayName(m.attachment_url);
            const iconBg = m.attachment_type === 'pdf' ? '#c0392b' : '#1d6f42';
            attachmentHtml = '<a href="' + m.attachment_url + '" target="_blank" rel="noopener" class="email-attachment">' +
              '<span class="email-attachment-icon" style="background:' + iconBg + ';"><i class="ti ' + icon + '"></i></span>' +
              '<span class="email-attachment-name">' + fileName + '</span>' +
              '</a>';`;

if (!content.includes(oldLine)) {
  console.error('ERROR: could not find the attachment link line in inbox.html.');
  process.exit(1);
}
content = content.replace(oldLine, newLine);

// 2. Add the filename-extraction helper and CSS, right before the closing </script>
const scriptCloseAnchor = `  </script>\n</body>\n</html>`;
const helperAndStyle = `    function attachmentDisplayName(url) {
      try {
        const rawName = decodeURIComponent(url.split('/').pop().split('?')[0]);
        // Storage filenames are "uuid-timestamp-originalname.ext" -- strip
        // that prefix to recover the real name the person uploaded.
        const stripped = rawName.replace(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-\\d+-/i, '');
        return stripped || rawName;
      } catch (e) {
        return 'Attachment';
      }
    }
  </script>
</body>
</html>`;

if (!content.includes(scriptCloseAnchor)) {
  console.error('ERROR: could not find the closing script/body/html tags in inbox.html.');
  process.exit(1);
}
content = content.replace(scriptCloseAnchor, helperAndStyle);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/inbox.html (file-manager-style attachment display).');

// 3. Append the new attachment-chip styles to the page's own CSS file,
//    since this page uses external stylesheets, not an inline <style> block
const cssPath = 'portal/assets/portal-inbox.css';
let { normalized: cssContent, usesCRLF: cssUsesCRLF } = readNormalized(cssPath);

const newStyles = `
.email-attachment{ display:inline-flex; align-items:center; gap:9px; text-decoration:none; padding:8px 12px 8px 8px; border:1px solid var(--border); border-radius:10px; background:var(--surface); margin-top:8px; transition:border-color 0.12s ease; }
.email-attachment:hover{ border-color:var(--primary); }
.email-attachment-icon{ width:30px; height:30px; border-radius:7px; display:flex; align-items:center; justify-content:center; color:#fff; flex-shrink:0; }
.email-attachment-icon i{ font-size:16px; }
.email-attachment-name{ font-size:12.5px; font-weight:600; color:var(--text-primary); }
`;

if (!cssContent.includes('.email-attachment-icon')) {
  cssContent += newStyles;
  writeRestoringLineEndings(cssPath, cssContent, cssUsesCRLF);
  console.log('    Appended attachment-chip styles to portal/assets/portal-inbox.css.');
} else {
  console.log('    Styles already present in portal-inbox.css -- skipped.');
}
NODE_EOF

node .tmp-patch-attach.js
rm .tmp-patch-attach.js

echo ""
echo "Done. Push with your usual save-progress.sh."
