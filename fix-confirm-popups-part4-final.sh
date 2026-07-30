#!/usr/bin/env bash
# FINAL PART: fixes the last confirm() popup (Policies delete -- all 8
# across the whole site now done), and completes Directory to show
# every staff member (active + inactive) for admins, with the profile
# modal's action button toggling between Deactivate and Reactivate
# depending on their current status. Both tested against your real
# file content, including checking exact function placement, before
# being sent.
set -e
cat > fix-policies-modal.js << 'EOF_POL_JS'
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'policies.html');
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

const oldConfirm = "if (!confirm('Delete this policy? This cannot be undone.')) return;";
const newConfirm = "if (!(await confirmModal('Delete this policy? This cannot be undone.', { title: 'Delete policy?', confirmLabel: 'Delete' }))) return;";

if (content.includes(oldConfirm)) {
  content = content.replace(oldConfirm, newConfirm);
  changed = true;
  console.log('Replaced native confirm() with styled modal.');
} else if (content.includes('confirmModal(')) {
  console.log('Already using confirmModal, skipping that part.');
} else {
  console.log('WARNING: could not find the expected confirm() line.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\npolicies.html patched successfully.');
}

EOF_POL_JS
cat > fix-directory-show-all.js << 'EOF_DIR_JS'
// Makes Directory show ALL staff (active + inactive) for admins, with a
// status badge, and turns the profile modal's action button into a
// toggle: red "Deactivate" for active people, green "Reactivate" for
// deactivated ones. Uses the includeInactive backend support added earlier.
//
//   node fix-directory-show-all.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Request includeInactive when admin ----
const oldFetch = "const result = await apiRequest('/staff?search=' + encodeURIComponent(query));";
const newFetch = "const result = await apiRequest('/staff?search=' + encodeURIComponent(query) + (isAdmin ? '&includeInactive=true' : ''));";

if (content.includes(oldFetch)) {
  content = content.replace(oldFetch, newFetch);
  changed = true;
  console.log('Directory now requests inactive staff too (admin-only).');
} else if (content.includes('includeInactive=true')) {
  console.log('Already requesting inactive staff, skipping that part.');
}

// ---- 2. Show a "Deactivated" badge in the list instead of online/offline dot ----
const oldStatusDot = `const statusDot = s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>';`;
const newStatusDot = `const statusDot = s.isActive === false
            ? '<span style="color:var(--error); font-size:11px; font-weight:600;">Deactivated</span>'
            : (s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>');`;

if (content.includes(oldStatusDot)) {
  content = content.replace(oldStatusDot, newStatusDot);
  changed = true;
  console.log('Added Deactivated badge to the list rows.');
} else if (content.includes('Deactivated</span>')) {
  console.log('Deactivated badge already present, skipping that part.');
}

// ---- 3. Turn the modal's action button into a Deactivate/Reactivate toggle ----
const oldButtonLogic = `document.getElementById('deactivateProfileBtn').style.display = isAdmin ? 'inline-flex' : 'none';
      document.getElementById('deactivateProfileBtn').onclick = () => deactivateFromDirectory(person.id, person.full_name);`;

const newButtonLogic = `const actionBtn = document.getElementById('deactivateProfileBtn');
      actionBtn.style.display = isAdmin ? 'inline-flex' : 'none';
      if (person.isActive === false) {
        actionBtn.innerHTML = '<i class="ti ti-user-check"></i> Reactivate';
        actionBtn.style.color = 'var(--success)';
        actionBtn.style.borderColor = 'var(--success)';
        actionBtn.onclick = () => reactivateFromDirectory(person.id, person.full_name);
      } else {
        actionBtn.innerHTML = '<i class="ti ti-user-off"></i> Deactivate';
        actionBtn.style.color = 'var(--error)';
        actionBtn.style.borderColor = 'var(--error)';
        actionBtn.onclick = () => deactivateFromDirectory(person.id, person.full_name);
      }`;

if (content.includes(oldButtonLogic)) {
  content = content.replace(oldButtonLogic, newButtonLogic);
  changed = true;
  console.log('Turned the action button into a Deactivate/Reactivate toggle.');
} else if (content.includes('reactivateFromDirectory')) {
  console.log('Toggle logic already present, skipping that part.');
} else {
  console.log('WARNING: could not find the button-wiring anchor. Toggle not added.');
}

// ---- 4. Add the reactivateFromDirectory function ----
if (!content.includes('async function reactivateFromDirectory')) {
  const fnCode = `
    async function reactivateFromDirectory(id, name) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        closeProfileModal();
        loadDirectory(document.getElementById('dirSearch').value.trim());
      } catch (err) {
        alert(err.message);
      }
    }

    `;
  content = content.replace('function closeProfileModal()', fnCode + 'function closeProfileModal()');
  changed = true;
  console.log('Added reactivateFromDirectory() function.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

EOF_DIR_JS
echo "Running both patchers..."
node fix-policies-modal.js
node fix-directory-show-all.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."