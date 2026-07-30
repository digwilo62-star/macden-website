// Replaces both native confirm() popups in Settings (Log out of all
// devices, and Disable 2FA) with the shared styled modal.
//
//   node fix-settings-modal.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'settings.html');
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

const replacements = [
  {
    old: "if (!confirm('This will sign you out on every device, including this one. Continue?')) return;",
    new: "if (!(await confirmModal('This will sign you out on every device, including this one. Continue?', { title: 'Log out everywhere?', confirmLabel: 'Log Out' }))) return;",
    label: 'Log out all devices confirm'
  },
  {
    old: "if (!confirm('Disable two-factor authentication on your account?')) return;",
    new: "if (!(await confirmModal('Disable two-factor authentication on your account?', { title: 'Disable 2FA?', confirmLabel: 'Disable' }))) return;",
    label: 'Disable 2FA confirm'
  }
];

replacements.forEach(({ old, new: newStr, label }) => {
  if (content.includes(old)) {
    content = content.replace(old, newStr);
    changed = true;
    console.log('Replaced ' + label + ' with styled modal.');
  } else if (!content.includes(newStr)) {
    console.log('WARNING: could not find ' + label + '. Nothing changed for that part.');
  } else {
    console.log(label + ' already updated, skipping.');
  }
});

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nsettings.html patched successfully.');
}

