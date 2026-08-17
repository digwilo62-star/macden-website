#!/bin/bash
# fix-word-attachment-support-v1.sh
#
# Adds Word (.docx) as an accepted attachment type, alongside the
# existing PDF and Excel support:
#   - Backend now accepts .docx uploads (was previously rejected outright)
#   - Compose's file picker now allows selecting .docx files
#   - Inbox shows a proper blue Word icon for them, alongside the
#     existing green Excel and red PDF icons

set -e

if grep -q "wordprocessingml" server/routes/messages.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-word.js << 'NODE_EOF'
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

// ---------- 1. server/routes/messages.js ----------
{
  const filePath = 'server/routes/messages.js';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const oldFilter = `    const allowed = {
      'application/pdf': 'pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx'
    };
    if (allowed[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF and Excel (.xlsx) files are allowed.'));
    }`;
  const newFilter = `    const allowed = {
      'application/pdf': 'pdf',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx'
    };
    if (allowed[file.mimetype]) {
      cb(null, true);
    } else {
      cb(new Error('Only PDF, Excel (.xlsx), and Word (.docx) files are allowed.'));
    }`;

  if (!content.includes(oldFilter)) {
    console.error('ERROR: could not find the fileFilter block in messages.js.');
    process.exit(1);
  }
  content = content.replace(oldFilter, newFilter);

  const oldTypeMap = `      const typeMap = {
        'application/pdf': 'pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx'
      };`;
  const newTypeMap = `      const typeMap = {
        'application/pdf': 'pdf',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx'
      };`;

  if (!content.includes(oldTypeMap)) {
    console.error('ERROR: could not find the typeMap block in messages.js.');
    process.exit(1);
  }
  content = content.replace(oldTypeMap, newTypeMap);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched server/routes/messages.js (accepts .docx uploads).');
}

// ---------- 2. portal/compose.html ----------
{
  const filePath = 'portal/compose.html';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const oldAccept = `<input type="file" id="fileInput" accept=".pdf,.xlsx" style="display:none;">`;
  const newAccept = `<input type="file" id="fileInput" accept=".pdf,.xlsx,.docx" style="display:none;">`;

  if (!content.includes(oldAccept)) {
    console.error('ERROR: could not find the file input in compose.html.');
    process.exit(1);
  }
  content = content.replace(oldAccept, newAccept);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched portal/compose.html (file picker allows .docx).');
}

// ---------- 3. portal/inbox.html ----------
{
  const filePath = 'portal/inbox.html';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const oldIconLogic = `            const icon = m.attachment_type === 'pdf' ? 'ti-file-type-pdf' : 'ti-file-spreadsheet';
            const fileName = attachmentDisplayName(m.attachment_url);
            const iconBg = m.attachment_type === 'pdf' ? '#c0392b' : '#1d6f42';`;
  const newIconLogic = `            const fileName = attachmentDisplayName(m.attachment_url);
            const iconInfo = { pdf: { icon: 'ti-file-type-pdf', bg: '#c0392b' }, xlsx: { icon: 'ti-file-spreadsheet', bg: '#1d6f42' }, docx: { icon: 'ti-file-type-doc', bg: '#2b579a' } }[m.attachment_type] || { icon: 'ti-file', bg: '#666' };
            const icon = iconInfo.icon;
            const iconBg = iconInfo.bg;`;

  if (!content.includes(oldIconLogic)) {
    console.error('ERROR: could not find the icon-selection logic in inbox.html.');
    process.exit(1);
  }
  content = content.replace(oldIconLogic, newIconLogic);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched portal/inbox.html (3-way icon: PDF red, Excel green, Word blue).');
}
NODE_EOF

node .tmp-patch-word.js
rm .tmp-patch-word.js

echo ""
echo "Done. Push with your usual save-progress.sh."
