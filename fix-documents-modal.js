// Replaces the native confirm() popup in Documents' delete flow with the
// shared styled modal.
//
//   node fix-documents-modal.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'documents.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

if (!content.includes('assets/confirm-modal.js')) {
  content = content.replace(
    '<script src="assets/api.js"></script>',
    '<script src="assets/api.js"></script>\n  <script src="assets/confirm-modal.js"></script>'
  );
  changed = true;
  console.log('Added confirm-modal.js script tag.');
} else {
  console.log('confirm-modal.js already linked, skipping that part.');
}

const oldConfirm = "if (!confirm('Delete this document? This cannot be undone.')) return;";
const newConfirm = "if (!(await confirmModal('Delete this document? This cannot be undone.', { title: 'Delete document?', confirmLabel: 'Delete' }))) return;";

if (content.includes(oldConfirm)) {
  content = content.replace(oldConfirm, newConfirm);
  changed = true;
  console.log('Replaced native confirm() with styled modal.');
} else if (content.includes('confirmModal(')) {
  console.log('Already using confirmModal, skipping that part.');
} else {
  console.log('WARNING: could not find the expected confirm() line. Nothing changed for that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndocuments.html patched successfully.');
}

