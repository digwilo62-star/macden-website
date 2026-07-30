// Replaces the native confirm() popup in Directory's deactivate flow with
// the shared styled modal.
//
//   node fix-directory-modal.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'directory.html');
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

const oldConfirm = "if (!confirm('Deactivate ' + name + '? They will no longer be able to log in. This can be undone later from Manage Staff.')) return;";
const newConfirm = "if (!(await confirmModal('Deactivate ' + name + '? They will no longer be able to log in. This can be undone later from Manage Staff.', { title: 'Deactivate staff member?', confirmLabel: 'Deactivate' }))) return;";

if (content.includes(oldConfirm)) {
  content = content.replace(oldConfirm, newConfirm);
  changed = true;
  console.log('Replaced native confirm() with styled modal.');
} else if (content.includes('confirmModal(')) {
  console.log('Already using confirmModal, skipping that part.');
} else {
  console.log('WARNING: could not find the expected confirm() line -- checking for a slightly different version...');
  // The exact wording had a spacing quirk in earlier pastes ("nolonger") -- try that too
  const altConfirm = "if (!confirm('Deactivate ' + name + '? They will nolonger be able to log in. This can be undone later from Manage Staff.')) return;";
  if (content.includes(altConfirm)) {
    content = content.replace(altConfirm, newConfirm.replace('will no longer', 'will nolonger'));
    changed = true;
    console.log('Replaced (alt-wording version) native confirm() with styled modal.');
  } else {
    console.log('Still not found. Nothing changed for that part -- paste back the real file if this persists.');
  }
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

