const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
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
      .select('id, full_name, username, email, role, phone, branch, is_active, created_at, departments(name)')
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

    if (!fullName || !email || !role || !departmentId) {
      return res.status(400).json({ error: 'Full name, email, role, and department are required.' });
    }

    // Generate a username from the name, and a random temporary password
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    const tempPassword = crypto.randomBytes(6).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 10);
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { data, error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        nin: nin || null,
        address: address || null,
        branch: branch || null,
        reports_to: reportsTo || null,
        email_verified: true,  // HR-created accounts are trusted, skip the self-signup flow
        is_active: true
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

    res.json({ success: true, staff: data });
  } catch (err) {
    console.error('Onboard staff unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating this account.' });
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
    res.json({ success: true });
  } catch (err) {
    console.error('Reactivate unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/admin/pending-staff
// Lists everyone who has verified their email but is still waiting on approval.
router.get('/pending-staff', async (req, res) => {
  const { data, error } = await supabase
    .from('staff')
    .select('id, full_name, username, email, created_at')
    .eq('email_verified', true)
    .eq('is_active', false)
    .order('created_at', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load pending accounts.' });
  }

  res.json({ pending: data });
});

// POST /api/accounting/admin/approve-staff/:id
router.post('/approve-staff/:id', async (req, res) => {
  const { id } = req.params;

  const { data, error } = await supabase
    .from('staff')
    .update({ is_active: true })
    .eq('id', id)
    .select()
    .single();

  if (error || !data) {
    return res.status(400).json({ error: 'Could not approve this account.' });
  }

  res.json({ success: true, message: `${data.full_name} has been approved and can now log in.` });
});

// DELETE /api/accounting/admin/staff/:id
// Deactivates a staff member (soft-disable, not a hard delete — their past
// messages and price edits stay intact) and clears any shared conversation
// with the admin performing this action.
router.delete('/staff/:id', async (req, res) => {
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
    return res.status(500).json({ error: 'Could not deactivate this account.' });
  }

  res.json({ success: true });
});

module.exports = router;

