#!/usr/bin/env bash
# PART 1 of the confirm()-popup fix: replaces native browser confirm()
# with a styled modal, matching the rest of the portal. This covers
# Directory and Manage Staff (2 of 8 total confirm() calls found).
# The remaining 4 files (documents.html, policies.html,
# pending-registrations.html, settings.html) need their real content
# pasted back before being safely patched -- same discipline as
# everything else this session, not guessing at file structure.
set -e
mkdir -p accounting/assets
cat > accounting/assets/confirm-modal.js << 'EOF_MODAL_JS'
// Shared, promise-based confirm dialog -- replaces native browser confirm()
// popups everywhere with a styled modal matching the rest of the portal.
// Self-contained (injects its own styles), so it doesn't depend on any
// other stylesheet being loaded on the page.
//
// Usage:  if (!(await confirmModal('Delete this?'))) return;

function confirmModal(message, options = {}) {
  return new Promise((resolve) => {
    const title = options.title || 'Are you sure?';
    const confirmLabel = options.confirmLabel || 'Confirm';
    const danger = options.danger !== false; // red confirm button by default

    const backdrop = document.createElement('div');
    backdrop.style.cssText = 'position:fixed; inset:0; background:rgba(0,0,0,0.45); display:flex; align-items:center; justify-content:center; z-index:9999;';

    const modal = document.createElement('div');
    modal.style.cssText = 'width:340px; background:#fff; border-radius:14px; padding:22px; font-family:-apple-system,sans-serif; box-shadow:0 10px 30px rgba(0,0,0,0.2);';

    const titleEl = document.createElement('h3');
    titleEl.textContent = title;
    titleEl.style.cssText = 'margin:0 0 10px; font-size:15px; color:#1a1a1a;';

    const msgEl = document.createElement('p');
    msgEl.textContent = message;
    msgEl.style.cssText = 'margin:0 0 20px; font-size:13px; color:#555; line-height:1.5;';

    const actions = document.createElement('div');
    actions.style.cssText = 'display:flex; gap:8px; justify-content:flex-end;';

    const cancelBtn = document.createElement('button');
    cancelBtn.textContent = 'Cancel';
    cancelBtn.style.cssText = 'padding:8px 16px; border-radius:8px; border:1px solid #ddd; background:#fff; cursor:pointer; font-size:13px;';

    const confirmBtn = document.createElement('button');
    confirmBtn.textContent = confirmLabel;
    confirmBtn.style.cssText = 'padding:8px 16px; border-radius:8px; border:none; cursor:pointer; font-size:13px; font-weight:600; color:#fff; background:' + (danger ? '#dc2626' : '#0d5c2f') + ';';

    function close(result) {
      document.body.removeChild(backdrop);
      resolve(result);
    }

    cancelBtn.onclick = () => close(false);
    confirmBtn.onclick = () => close(true);
    backdrop.onclick = (e) => { if (e.target === backdrop) close(false); };

    actions.appendChild(cancelBtn);
    actions.appendChild(confirmBtn);
    modal.appendChild(titleEl);
    modal.appendChild(msgEl);
    modal.appendChild(actions);
    backdrop.appendChild(modal);
    document.body.appendChild(backdrop);

    confirmBtn.focus();
  });
}

EOF_MODAL_JS
cat > fix-manage-staff-modal.js << 'EOF_MS_JS'
// Replaces the native confirm() popup in Manage Staff's deactivate flow
// with the shared styled modal.
//
//   node fix-manage-staff-modal.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'manage-staff.html');
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

const oldConfirm = "if (!confirm('Deactivate this staff member? They will no longer be able to log in.')) return;";
const newConfirm = "if (!(await confirmModal('Deactivate this staff member? They will no longer be able to log in.', { title: 'Deactivate staff member?', confirmLabel: 'Deactivate' }))) return;";

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
  console.log('\nmanage-staff.html patched successfully.');
}

EOF_MS_JS
cat > fix-directory-modal.js << 'EOF_DIR_JS'
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

EOF_DIR_JS
echo "Running both patchers..."
node fix-manage-staff-modal.js
node fix-directory-modal.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."