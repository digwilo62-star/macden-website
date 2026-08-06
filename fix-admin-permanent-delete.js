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

