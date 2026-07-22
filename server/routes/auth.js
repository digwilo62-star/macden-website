const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const supabase = require('../config/supabaseClient');
const { sendVerificationEmail } = require('../utils/email');

const router = express.Router();

// Limits brute-force login attempts and signup/verification abuse.
// 10 attempts per 15 minutes per IP is generous for a real person, tight for a script.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please wait a few minutes and try again.' }
});

function generateCode() {
  // 6-digit numeric code, e.g. 483920
  return crypto.randomInt(100000, 999999).toString();
}

// POST /api/accounting/auth/register
router.post('/register', authLimiter, async (req, res) => {
  const { fullName, username, email, password } = req.body;

  if (!fullName || !username || !email || !password) {
    return res.status(400).json({ error: 'All fields are required.' });
  }

  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters.' });
  }

  const { data: dept, error: deptError } = await supabase
    .from('departments')
    .select('id')
    .eq('slug', 'accounting')
    .single();

  if (deptError || !dept) {
    return res.status(500).json({ error: 'Setup error — accounting department not found.' });
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const code = generateCode();
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes from now

  const { data: newStaff, error } = await supabase
    .from('staff')
    .insert({
      department_id: dept.id,
      full_name: fullName,
      username: username,
      email: email,
      password_hash: passwordHash,
      email_verified: false,
      is_active: false, // stays inactive until you manually approve
      verification_code: code,
      verification_code_expires_at: expiresAt.toISOString()
    })
    .select()
    .single();

  if (error) {
    // Most likely cause: username or email already taken (unique constraint)
    return res.status(400).json({ error: 'Could not create account. Username or email may already be in use.' });
  }

  try {
    await sendVerificationEmail(email, fullName, code);
  } catch (emailError) {
    console.error('Failed to send verification email:', emailError.message);
    return res.status(500).json({ error: 'Account created but the verification email failed to send. Contact your admin.' });
  }

  res.json({ success: true, message: 'Account created. Check your email for a verification code.' });
});

// POST /api/accounting/auth/verify-email
router.post('/verify-email', authLimiter, async (req, res) => {
  const { email, code } = req.body;

  if (!email || !code) {
    return res.status(400).json({ error: 'Email and code are required.' });
  }

  const { data: staffMember, error } = await supabase
    .from('staff')
    .select('id, verification_code, verification_code_expires_at, email_verified')
    .eq('email', email)
    .single();

  if (error || !staffMember) {
    return res.status(400).json({ error: 'Invalid email or code.' });
  }

  if (staffMember.email_verified) {
    return res.status(400).json({ error: 'This email is already verified.' });
  }

  if (staffMember.verification_code !== code) {
    return res.status(400).json({ error: 'Incorrect code.' });
  }

  if (new Date(staffMember.verification_code_expires_at) < new Date()) {
    return res.status(400).json({ error: 'This code has expired. Please request a new one.' });
  }

  await supabase
    .from('staff')
    .update({ email_verified: true, verification_code: null, verification_code_expires_at: null })
    .eq('id', staffMember.id);

  res.json({ success: true, message: 'Email verified. Your account is now waiting for admin approval.' });
});

// POST /api/accounting/auth/login
router.post('/login', authLimiter, async (req, res) => {
  const { username, password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Email and password are required.' });
  }

  // The new portal design logs in with email, but existing accounts (and the
  // CLI script) are keyed by username — accept either so nothing breaks.
  const isEmail = username.includes('@');
  const { data: staffMember, error } = await supabase
    .from('staff')
    .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, email_verified, department_id')
    .eq(isEmail ? 'email' : 'username', username)
    .single();

  if (error || !staffMember) {
    return res.status(401).json({ error: 'Invalid email or password.' });
  }

  const passwordMatches = await bcrypt.compare(password, staffMember.password_hash);

  if (!passwordMatches) {
    return res.status(401).json({ error: 'Invalid email or password.' });
  }

  if (!staffMember.email_verified) {
    return res.status(403).json({ error: 'Please verify your email before logging in.' });
  }

  if (!staffMember.is_active) {
    return res.status(403).json({ error: 'Your account is awaiting admin approval.' });
  }

  // Store only what we need in the session — never the password hash
  req.session.staff = {
    id: staffMember.id,
    fullName: staffMember.full_name,
    username: staffMember.username,
    role: staffMember.role,
    canEditPrices: staffMember.can_edit_prices,
    departmentId: staffMember.department_id
  };

  await supabase
    .from('staff')
    .update({ last_seen: new Date().toISOString() })
    .eq('id', staffMember.id);

  res.json({ success: true, staff: req.session.staff });
});

// POST /api/accounting/auth/logout
router.post('/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      return res.status(500).json({ error: 'Could not log out. Try again.' });
    }
    res.clearCookie('connect.sid');
    res.json({ success: true });
  });
});

// GET /api/accounting/auth/me — used by frontend to check if a session is active
router.get('/me', (req, res) => {
  if (!req.session.staff) {
    return res.status(401).json({ error: 'Not logged in.' });
  }
  res.json({ staff: req.session.staff });
});

module.exports = router;

