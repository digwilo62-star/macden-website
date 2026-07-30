




#!/usr/bin/env bash
# PART 3: fixes the remaining 4 of 8 confirm() popups -- Pending
# Registrations (Approve, Reject) and Settings (Log out everywhere,
# Disable 2FA). All 8 across the whole site are now covered once this
# runs. Both tested against your real file content before being sent.
set -e
cat > fix-pending-reg-modal.js << 'EOF_PR_JS'
// Replaces both native confirm() popups in Pending Registrations (Approve
// and Reject flows) with the shared styled modal.
//
//   node fix-pending-reg-modal.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'pending-registrations.html');
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
    old: "if (!confirm('Approve this registration? They will be emailed their login details.')) return;",
    new: "if (!(await confirmModal('Approve this registration? They will be emailed their login details.', { title: 'Approve registration?', confirmLabel: 'Approve', danger: false }))) return;",
    label: 'Approve confirm'
  },
  {
    old: "if (!confirm('Reject this registration? This cannot be undone.')) return;",
    new: "if (!(await confirmModal('Reject this registration? This cannot be undone.', { title: 'Reject registration?', confirmLabel: 'Reject' }))) return;",
    label: 'Reject confirm'
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
  console.log('\npending-registrations.html patched successfully.');
}

EOF_PR_JS
cat > fix-settings-modal.js << 'EOF_SET_JS'
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

EOF_SET_JS
echo "Running both patchers..."
node fix-pending-reg-modal.js
node fix-settings-modal.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."