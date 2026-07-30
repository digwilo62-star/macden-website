const express = require('express');
const crypto = require('crypto');
const supabase = require('../config/supabaseClient');
const { sendWelcomeEmail } = require('../utils/email');

const router = express.Router();

// Self-contained admin check (doesn't depend on the exact contents of
// admin.js, since this is a separate router mounted independently).
function requireAdmin(req, res, next) {
  if (!req.session.staff || req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

router.use(requireAdmin);

// GET /api/accounting/registrations/pending — everyone who submitted the
// public form and hasn't been approved or rejected yet
router.get('/pending', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, phone, branch, created_at, departments(name)')
      .eq('is_active', false)
      .eq('email_verified', true)
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Pending registrations fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending registrations.' });
    }

    const pending = data.map(p => ({
      id: p.id,
      fullName: p.full_name,
      username: p.username,
      email: p.email,
      phone: p.phone,
      branch: p.branch,
      department: p.departments ? p.departments.name : null,
      submittedAt: p.created_at
    }));

    res.json({ pending });
  } catch (err) {
    console.error('Pending registrations unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading pending registrations.' });
  }
});

// POST /api/accounting/registrations/:id/approve — generates a real
// password, activates the account, emails the credentials
router.post('/:id/approve', async (req, res) => {
  try {
    const { id } = req.params;

    const { data: person, error: fetchError } = await supabase
      .from('staff')
      .select('id, full_name, username, email, is_active')
      .eq('id', id)
      .single();

    if (fetchError || !person) {
      return res.status(404).json({ error: 'Registration not found.' });
    }
    if (person.is_active) {
      return res.status(400).json({ error: 'This registration has already been approved.' });
    }

    const tempPassword = crypto.randomBytes(14).toString('base64').replace(/[^a-zA-Z0-9]/g, '').slice(0, 14);
    const bcrypt = require('bcrypt');
    const passwordHash = await bcrypt.hash(tempPassword, 10);

    const { error: updateError } = await supabase
      .from('staff')
      .update({
        password_hash: passwordHash,
        is_active: true,
        must_change_password: true
      })
      .eq('id', id);

    if (updateError) {
      console.error('Approve registration update error:', updateError);
      return res.status(500).json({ error: 'Could not approve this registration.' });
    }

    try {
      await sendWelcomeEmail(person.email, person.full_name, person.username, tempPassword);
    } catch (emailErr) {
      console.error('Approval welcome email failed:', emailErr);
      return res.json({
        success: true,
        warning: 'Account approved, but the welcome email failed to send. Username: ' + person.username + ', temporary password: ' + tempPassword
      });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Approve registration unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong approving this registration.' });
  }
});

// POST /api/accounting/registrations/:id/reject — deletes the pending record entirely
router.post('/:id/reject', async (req, res) => {
  try {
    const { id } = req.params;
    const { error } = await supabase.from('staff').delete().eq('id', id).eq('is_active', false);
    if (error) {
      return res.status(500).json({ error: 'Could not reject this registration.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Reject registration unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

