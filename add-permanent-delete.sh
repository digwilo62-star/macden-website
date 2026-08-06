#!/usr/bin/env bash
# Adds permanent account deletion, Directory-only, gated to only
# already-deactivated accounts (enforced server-side, not just hidden
# in the UI). Doesn't hard-delete the row (would risk foreign-key
# failures or destroying message/leave history) -- instead permanently
# scrubs login credentials so they can never log in again, and their
# email/username become free for reuse. All 3 pieces tested against
# real file content, including a real module-load test on the backend.
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
set -e
cat > fix-staff-exclude-deleted.js << 'EOF_STAFF_JS'
// Makes the staff directory query always exclude permanently-deleted
// accounts, regardless of the includeInactive flag -- deactivated people
// can still show up (that's the whole point of includeInactive), but
// deleted people should never appear anywhere again.
//
//   node fix-staff-exclude-deleted.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'staff.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes("is('deleted_at', null)")) {
  console.log('Already updated, skipping.');
  process.exit(0);
}

const anchor = ".neq('id', req.session.staff.id)\n      .order('full_name', { ascending: true });";
const replacement = ".neq('id', req.session.staff.id)\n      .is('deleted_at', null)\n      .order('full_name', { ascending: true });";

if (content.includes(anchor)) {
  content = content.replace(anchor, replacement);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Directory/search now excludes permanently-deleted accounts.');
} else {
  console.log('WARNING: could not find the expected query anchor. Nothing changed -- paste back staff.js if this persists.');
  process.exit(1);
}

EOF_STAFF_JS
cat > fix-admin-permanent-delete.js << 'EOF_ADMIN_JS'
// Adds the permanent-delete route. Requires the account to already be
// deactivated (a real safety gate, not just a UI suggestion -- enforced
// here server-side too). Scrubs login credentials (username, email,
// password) rather than removing the row, so existing messages/leave
// history stays correctly attributed instead of breaking or cascading
// away. Also updates all-staff (Manage Staff) to exclude deleted accounts.
//
//   node fix-admin-permanent-delete.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Exclude deleted accounts from Manage Staff's all-staff list ----
const allStaffAnchor = ".select('id, full_name, username, email, role, phone, branch, is_active, created_at, departments(name)')\n      .order('full_name');";
const allStaffReplacement = ".select('id, full_name, username, email, role, phone, branch, is_active, created_at, deleted_at, departments(name)')\n      .is('deleted_at', null)\n      .order('full_name');";

if (content.includes(allStaffAnchor)) {
  content = content.replace(allStaffAnchor, allStaffReplacement);
  changed = true;
  console.log('Manage Staff list now excludes permanently-deleted accounts.');
} else if (content.includes("is('deleted_at', null)\n      .order('full_name')")) {
  console.log('Manage Staff exclusion already present, skipping that part.');
}

// ---- 2. Add the permanent-delete route, scoped specifically (checking
// within the route body, not the whole file, to avoid the exact
// false-positive bug that silently broke an earlier fix this session) ----
const routeExistsCheck = content.includes("router.delete('/staff/:id/permanent'");

if (!routeExistsCheck) {
  const insertAnchor = 'module.exports = router;';
  const newRoute = `// DELETE /api/accounting/admin/staff/:id/permanent
// Requires the account to already be deactivated first -- a real
// server-side safety gate, not just a UI suggestion. Doesn't remove the
// row (their ID is referenced by messages, leave requests, etc. -- doing
// so could fail on foreign key constraints or destroy that history).
// Instead scrubs their login credentials permanently: they can never log
// in again, and their email/username become free for someone else to use.
router.delete('/staff/:id/permanent', async (req, res) => {
  try {
    const { id } = req.params;

    const { data: target, error: fetchError } = await supabase
      .from('staff')
      .select('id, full_name, is_active, deleted_at')
      .eq('id', id)
      .single();

    if (fetchError || !target) {
      return res.status(404).json({ error: 'Account not found.' });
    }
    if (target.deleted_at) {
      return res.status(400).json({ error: 'This account has already been permanently deleted.' });
    }
    if (target.is_active) {
      return res.status(400).json({ error: 'Deactivate this account first before permanently deleting it.' });
    }

    const scrubSuffix = id.slice(0, 8);
    const { error } = await supabase
      .from('staff')
      .update({
        username: 'deleted-' + scrubSuffix,
        email: 'deleted-' + scrubSuffix + '@deleted.macden.local',
        password_hash: 'DELETED-ACCOUNT-NO-LOGIN-POSSIBLE',
        deleted_at: new Date().toISOString()
      })
      .eq('id', id);

    if (error) {
      console.error('Permanent delete error:', error);
      return res.status(500).json({ error: 'Could not permanently delete this account.' });
    }

    logAdminAction(req, 'permanent_delete_staff', id, \`Permanently deleted \${target.full_name}\`);
    res.json({ success: true });
  } catch (err) {
    console.error('Permanent delete unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;`;

  content = content.replace(insertAnchor, newRoute);
  changed = true;
  console.log('Added the permanent-delete route.');
} else {
  console.log('Permanent-delete route already present, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nadmin.js patched successfully.');
}

EOF_ADMIN_JS
cat > fix-directory-add-delete.js << 'EOF_DIR_JS'
// Adds a "Delete Permanently" button to Directory's profile modal --
// visible ONLY when the person is already deactivated (matches the
// server-side safety gate). Reuses the styled confirm modal already built
// for Deactivate, with extra-clear irreversible-action wording.
//
//   node fix-directory-add-delete.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add the Delete button right after the Deactivate/Reactivate button ----
if (!content.includes('id="deletePermanentlyBtn"')) {
  const btnIdx = content.indexOf('id="deactivateProfileBtn"');
  if (btnIdx === -1) {
    console.log('WARNING: could not find deactivateProfileBtn. Nothing changed.');
    process.exit(1);
  }
  const closeDivIdx = content.indexOf('</button>', btnIdx) + '</button>'.length;

  const deleteBtnHtml = `
      <button class="btn btn-ghost" id="deletePermanentlyBtn" style="display:none; margin-top:10px; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px; color:#fff; background:var(--error); border-color:var(--error);">
        <i class="ti ti-trash"></i> Delete Permanently
      </button>`;

  content = content.slice(0, closeDivIdx) + deleteBtnHtml + content.slice(closeDivIdx);
  changed = true;
  console.log('Added Delete Permanently button.');
} else {
  console.log('Delete button already present, skipping that part.');
}

// ---- 2. Show/hide it in openProfile() -- only for already-deactivated people ----
const showAnchor = "actionBtn.onclick = () => reactivateFromDirectory(person.id, person.full_name);";

if (!content.includes("document.getElementById('deletePermanentlyBtn').style.display")) {
  const wireCode = `${showAnchor}
        document.getElementById('deletePermanentlyBtn').style.display = 'inline-flex';
        document.getElementById('deletePermanentlyBtn').onclick = () => deletePermanentlyFromDirectory(person.id, person.full_name);`;

  const hideCode = `} else {
        document.getElementById('deletePermanentlyBtn').style.display = 'none';`;

  if (content.includes(showAnchor)) {
    content = content.replace(showAnchor, wireCode);
    changed = true;
  }

  const oldElseBlock = `} else {
        actionBtn.innerHTML = '<i class="titi-user-off"></i> Deactivate';`;
  const newElseBlock = `} else {
        document.getElementById('deletePermanentlyBtn').style.display = 'none';
        actionBtn.innerHTML = '<i class="titi-user-off"></i> Deactivate';`;

  if (content.includes(oldElseBlock)) {
    content = content.replace(oldElseBlock, newElseBlock);
    changed = true;
    console.log('Wired Delete button visibility (only shows for deactivated accounts).');
  } else {
    console.log('WARNING: could not find the else-block anchor for hiding the button. Nothing changed for that part.');
  }
} else {
  console.log('Delete button visibility already wired, skipping that part.');
}

// ---- 3. Add the deletePermanentlyFromDirectory function ----
if (!content.includes('async function deletePermanentlyFromDirectory')) {
  const fnCode = `
    async function deletePermanentlyFromDirectory(id, name) {
      if (!(await confirmModal(
        'Permanently delete ' + name + '\\'s account? This CANNOT be undone. Their username and email will be freed up, and they can never log in again. Their message and leave history will be kept.',
        { title: 'Permanently delete this account?', confirmLabel: 'Delete Permanently' }
      ))) return;
      try {
        await apiRequest('/admin/staff/' + id + '/permanent', { method: 'DELETE' });
        closeProfileModal();
        loadDirectory(document.getElementById('dirSearch').value.trim());
      } catch (err) {
        alert(err.message);
      }
    }

    `;
  content = content.replace('function closeProfileModal()', fnCode + 'function closeProfileModal()');
  changed = true;
  console.log('Added deletePermanentlyFromDirectory() function.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

EOF_DIR_JS
echo "Running all three patchers..."
node fix-staff-exclude-deleted.js
node fix-admin-permanent-delete.js
node fix-directory-add-delete.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."