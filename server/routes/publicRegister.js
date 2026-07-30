const express = require('express');
const supabase = require('../config/supabaseClient');
const crypto = require('crypto');
const bcrypt = require('bcrypt');

const router = express.Router();

// GET /api/accounting/public/departments — no login needed, just for the
// registration form's dropdown (department names only, nothing sensitive).
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      console.error('Public departments fetch error:', error);
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Public departments unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/public/register — any staff member at any branch
// submits this. Creates a PENDING record (is_active: false) -- no account
// exists yet, no password is set, nothing is emailed. HR/Admin reviews and
// approves it from the Pending Registrations page before any of that happens.
router.post('/register', async (req, res) => {
  try {
    const { fullName, branch, departmentId, phone, email } = req.body;

    if (!fullName || !branch || !departmentId || !phone || !email) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    const { data: existing } = await supabase
      .from('staff')
      .select('id')
      .eq('email', email)
      .maybeSingle();

    if (existing) {
      return res.status(400).json({ error: 'An account with this email already exists or is already pending review.' });
    }

    // Generate a username now (so it's ready if/when approved), and a
    // random throwaway password hash as a placeholder -- this gets
    // replaced with a real one when HR approves the request.
    const baseUsername = fullName.toLowerCase().replace(/[^a-z]+/g, '.').replace(/^\.|\.$/g, '');
    const username = baseUsername + '.' + crypto.randomInt(100, 999);
    const placeholderHash = await bcrypt.hash(crypto.randomBytes(16).toString('hex'), 10);

    const { error } = await supabase
      .from('staff')
      .insert({
        full_name: fullName,
        username: username,
        email: email,
        phone: phone,
        branch: branch,
        department_id: departmentId,
        password_hash: placeholderHash,
        role: 'staff',
        is_active: false,
        email_verified: true // manual HR review replaces the email-code step for this flow
      });

    if (error) {
      console.error('Public register insert error:', error);
      return res.status(500).json({ error: 'Could not submit your registration. Please try again.' });
    }

    res.json({ success: true, message: 'Your registration has been submitted for review. HR will email your login details once approved.' });
  } catch (err) {
    console.error('Public register unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong submitting your registration.' });
  }
});

module.exports = router;

