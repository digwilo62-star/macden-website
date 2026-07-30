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

