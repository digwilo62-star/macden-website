const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');
const { encrypt, decrypt } = require('../utils/encryption');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

// Logs sensitive admin actions (who did what, when, from where) — closes the
// "who touched HR data" gap flagged when NIN/address fields were first added.
// Fire-and-forget: a logging failure should never block the actual action.
function logAdminAction(req, action, targetId, details) {
  supabase
    .from('admin_audit_log')
    .insert({
      staff_id: req.session.staff.id,
      action,
      target_id: targetId ? String(targetId) : null,
      details: details || null,
      ip_address: req.ip || req.headers['x-forwarded-for'] || null
    })
    .then(({ error }) => {
      if (error) console.error('Audit log insert failed:', error);
    });
}

router.use(requireAdmin);

// GET /api/accounting/admin/departments — for the onboarding Work Info dropdown
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Departments fetch error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/all-staff — everyone including inactive, for Manage Staff
router.get('/all-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, phone, branch, is_active, created_at, deleted_at, departments(name)')
      .is('deleted_at', null)
      .order('full_name');

    if (error) {
      console.error('All-staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load staff.' });
    }

    const staff = data.map(s => ({
      id: s.id,
      fullName: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      phone: s.phone,
      branch: s.branch,
      department: s.departments ? s.departments.name : null,
      isActive: s.is_active,
      dateStarted: s.created_at
    }));

    res.json({ staff });
  } catch (err) {
    console.error('All-staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading staff.' });
  }
});

// POST /api/accounting/admin/onboard-staff — HR-initiated account creation
router.post('/onboard-staff', async (req, res) => {
  try {
    const { fullName, email, phone, nin, address, role, departmentId, branch, dateStarted, reportsTo } = req.body;

    if (!fullName || !email || !role) {
      return res.status(400).json({ error: 'Full name, email, and role are required.' });
    }

    // Generate a username from the name, and a random temporary password
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    // Longer temp password (was 10 chars, now 14) — generate extra bytes
    // since base64/alphanumeric stripping shrinks the usable length.
    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        role: role,
        department_id: departmentId || null,
        phone: phone || null,
        nin: nin ? encrypt(nin) : null,
        address: address ? encrypt(address) : null,
        branch: branch || null,
        reports_to: reportsTo || null,
        email_verified: true,  // HR-created accounts are trusted, skip the self-signup flow
        is_active: true,
        must_change_password: true
      })
      .select()
      .single();

    if (error) {
      console.error('Onboard staff insert error:', error);
      return res.status(400).json({ error: 'Could not create account. Email may already be in use.' });
    }

    try {
      await sendWelcomeEmail(email, fullName, username, tempPassword);
    } catch (emailErr) {
      console.error('Welcome email failed:', emailErr);
      // Account was created successfully even if the email failed — tell the admin so they can share credentials manually
      return res.json({
        success: true,
        staff: data,
        warning: 'Account created, but the welcome email failed to send. Username: ' + username + ', temporary password: ' + tempPassword
      });
    }

    logAdminAction(req, 'onboard_staff', data.id, `Created account for ${fullName} (${email})`);
    res.json({ success: true, staff: data });
  } catch (err) {
    console.error('Onboard staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating this account.' });
  }
});

// GET /api/accounting/admin/staff/:id -- single staff record with the
// raw department_id (not just the joined name), needed to accurately
// pre-fill the Edit form before submitting changes back.
router.get('/staff/:id', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, role, department_id, phone, branch')
      .eq('id', req.params.id)
      .single();

    if (error || !data) {
      return res.status(404).json({ error: 'Staff member not found.' });
    }

    res.json({ staff: data });
  } catch (err) {
    console.error('Single staff fetch error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// PUT /api/accounting/admin/staff/:id — edit an existing staff member
router.put('/staff/:id', async (req, res) => {
  try {
    const { fullName, role, departmentId, phone, branch } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update this account.' });
    }
    logAdminAction(req, 'edit_staff', req.params.id, `Updated profile fields (role/department/phone/branch)`);
    res.json({ success: true });
  } catch (err) {
    console.error('Staff edit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/staff/:id/reactivate
router.post('/staff/:id/reactivate', async (req, res) => {
  try {
    const { error } = await supabase.from('staff').update({ is_active: true }).eq('id', req.params.id);
    if (error) {
      return res.status(500).json({ error: 'Could not reactivate this account.' });
    }
    logAdminAction(req, 'reactivate_staff', req.params.id, 'Reactivated account');
    res.json({ success: true });
  } catch (err) {
    console.error('Reactivate unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, created_at')
      .eq('email_verified', true)
      .eq('is_active', false)
      .is('deleted_at', null)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Pending staff fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending accounts.' });
    }

    res.json({ pending: data });
  } catch (err) {
    console.error('Pending staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
  console.log('[APPROVE-DEBUG] Request received for id:', req.params.id);
  try {
    const { id } = req.params;

    // Generate a fresh password (overwriting whatever they set during
    // self-registration) and force them to change it on first login --
    // same pattern already used for HR-onboarded accounts.
    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const newPasswordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .update({ is_active: true, password_hash: newPasswordHash, must_change_password: true })
      .eq('id', id)
      .select()
      .single();

    if (error || !data) {
      return res.status(400).json({ error: 'Could not approve this account.' });
    }

    logAdminAction(req, 'approve_staff', id, `Approved ${data.full_name}`);
    console.log('[APPROVE-DEBUG] Account approved in database. About to email:', data.email);

    try {
      await sendWelcomeEmail(data.email, data.full_name, data.username, tempPassword);
      console.log('[APPROVE-DEBUG] sendWelcomeEmail() completed with NO error thrown.');
    } catch (emailErr) {
      console.error('[APPROVE-DEBUG] Approval welcome email FAILED:', emailErr);
      return res.json({
        success: true,
        message: `${data.full_name} has been approved, but the email failed to send.`,
        warning: 'Email failed. Username: ' + data.username + ', temporary password: ' + tempPassword
      });
    }

    res.json({ success: true, message: `${data.full_name} has been approved and emailed their login details.` });
  } catch (err) {
    console.error('Approve staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this account.' });
  }
});

// DELETE /api/accounting/admin/staff/:id
// Deactivates a staff member (soft-disable, not a hard delete — their past
// messages and price edits stay intact) and clears any shared conversation
// with the admin performing this action.
router.delete('/staff/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const adminId = req.session.staff.id;

    if (id === adminId) {
      return res.status(400).json({ error: 'You cannot deactivate your own account.' });
    }

    const { data: targetMemberships } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', id);

    const { data: adminMemberships } = await supabase
      .from('conversation_members')
      .select('conversation_id')
      .eq('staff_id', adminId);

    const targetIds = new Set((targetMemberships || []).map(m => m.conversation_id));
    const sharedConversationIds = (adminMemberships || [])
      .map(m => m.conversation_id)
      .filter(convId => targetIds.has(convId));

    if (sharedConversationIds.length > 0) {
      // Cascade delete handles conversation_members, messages, and message_reads automatically
      await supabase.from('conversations').delete().in('id', sharedConversationIds);
    }

    const { error } = await supabase
      .from('staff')
      .update({ is_active: false })
      .eq('id', id);

    if (error) {
      console.error('Deactivate staff error:', error);
      return res.status(500).json({ error: 'Could not deactivate this account.' });
    }

    logAdminAction(req, 'deactivate_staff', id, 'Deactivated account');
    res.json({ success: true });
  } catch (err) {
    console.error('Deactivate staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong deactivating this account.' });
  }
});

// GET /api/accounting/admin/audit-log — recent sensitive admin actions
router.get('/audit-log', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('admin_audit_log')
      .select('id, staff_id, action, target_id, details, created_at')
      .order('created_at', { ascending: false })
      .limit(25);

    if (error) {
      console.error('Audit log fetch error:', error);
      return res.status(500).json({ error: 'Could not load the audit log.' });
    }

    const staffIds = [...new Set(data.map(l => l.staff_id).filter(Boolean))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name')
      .in('id', staffIds.length > 0 ? staffIds : ['00000000-0000-0000-0000-000000000000']);
    const nameById = {};
    (staffRows || []).forEach(s => { nameById[s.id] = s.full_name; });

    const entries = data.map(l => ({
      ...l,
      staffName: nameById[l.staff_id] || 'Unknown'
    }));

    res.json({ entries });
  } catch (err) {
    console.error('Audit log unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading the audit log.' });
  }
});

// DELETE /api/accounting/admin/staff/:id/permanent
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

    logAdminAction(req, 'permanent_delete_staff', id, `Permanently deleted ${target.full_name}`);
    res.json({ success: true });
  } catch (err) {
    console.error('Permanent delete unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

