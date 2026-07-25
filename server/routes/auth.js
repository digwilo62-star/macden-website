const express = require('express');
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const rateLimit = require('express-rate-limit');
const { authenticator } = require('otplib');
const supabase = require('../config/supabaseClient');
const { sendVerificationEmail } = require('../utils/email');

const router = express.Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please wait a few minutes and try again.' }
});

function generateCode() {
  return crypto.randomInt(100000, 999999).toString();
}

// POST /api/accounting/auth/register
router.post('/register', authLimiter, async (req, res) => {
  try {
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
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    const { data: newStaff, error } = await supabase
      .from('staff')
      .insert({
        department_id: dept.id,
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        email_verified: false,
        is_active: false,
        verification_code: code,
        verification_code_expires_at: expiresAt.toISOString()
      })
      .select()
      .single();

    if (error) {
      console.error('Register insert error:', error);
      return res.status(400).json({ error: 'Could not create account. Username or email may already be in use.' });
    }

    try {
      await sendVerificationEmail(email, fullName, code);
    } catch (emailError) {
      console.error('Failed to send verification email:', emailError.message);
      return res.status(500).json({ error: 'Account created but the verification email failed to send. Contact your admin.' });
    }

    res.json({ success: true, message: 'Account created. Check your email for a verification code.' });
  } catch (err) {
    console.error('Register unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating your account.' });
  }
});

// POST /api/accounting/auth/verify-email
router.post('/verify-email', authLimiter, async (req, res) => {
  try {
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

    const { error: updateError } = await supabase
      .from('staff')
      .update({ email_verified: true, verification_code: null, verification_code_expires_at: null })
      .eq('id', staffMember.id);

    if (updateError) {
      console.error('Verify-email update error:', updateError);
      return res.status(500).json({ error: 'Could not verify your email. Please try again.' });
    }

    res.json({ success: true, message: 'Email verified. Your account is now waiting for admin approval.' });
  } catch (err) {
    console.error('Verify-email unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong verifying your email.' });
  }
});

// POST /api/accounting/auth/login
router.post('/login', authLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'Email and password are required.' });
    }

    const isEmail = username.includes('@');
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, email_verified, department_id, must_change_password, mfa_enabled')
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

    // If this account has two-factor authentication enabled, don't complete
    // the login yet — password is correct, but we still need a valid TOTP
    // code before creating a real session. The pending staff ID lives in
    // the session itself (not req.session.staff), so requireAuth still
    // blocks access to everything until the second step succeeds.
    if (staffMember.mfa_enabled) {
      req.session.pendingMfaStaffId = staffMember.id;
      return res.json({ success: true, requiresMfa: true });
    }

    // Regenerate the session ID on login (not just reuse whatever session
    // existed before authentication) — prevents session fixation attacks,
    // where an attacker tricks someone into using a known session ID.
    req.session.regenerate((regenErr) => {
      if (regenErr) {
        console.error('Session regenerate error:', regenErr);
        return res.status(500).json({ error: 'Something went wrong logging you in.' });
      }

      req.session.staff = {
        id: staffMember.id,
        fullName: staffMember.full_name,
        username: staffMember.username,
        role: staffMember.role,
        canEditPrices: staffMember.can_edit_prices,
        departmentId: staffMember.department_id,
        mustChangePassword: staffMember.must_change_password
      };

      supabase
        .from('staff')
        .update({ last_seen: new Date().toISOString() })
        .eq('id', staffMember.id)
        .then(() => {
          res.json({ success: true, staff: req.session.staff });
        });
    });
  } catch (err) {
    console.error('Login unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging you in.' });
  }
});

// POST /api/accounting/auth/logout
// POST /api/accounting/auth/login-mfa — second step, completes login after
// the password step returned requiresMfa: true
router.post('/login-mfa', authLimiter, async (req, res) => {
  try {
    const { code } = req.body;
    const pendingStaffId = req.session.pendingMfaStaffId;

    if (!pendingStaffId) {
      return res.status(400).json({ error: 'Please log in with your password first.' });
    }
    if (!code) {
      return res.status(400).json({ error: 'Enter the 6-digit code from your authenticator app.' });
    }

    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('id, full_name, username, role, can_edit_prices, department_id, must_change_password, mfa_secret')
      .eq('id', pendingStaffId)
      .single();

    if (error || !staffMember) {
      return res.status(401).json({ error: 'Something went wrong. Please log in again.' });
    }

    const isValid = authenticator.verify({ token: code, secret: staffMember.mfa_secret });
    if (!isValid) {
      return res.status(401).json({ error: 'Incorrect code. Check your authenticator app and try again.' });
    }

    delete req.session.pendingMfaStaffId;

    req.session.regenerate((regenErr) => {
      if (regenErr) {
        console.error('MFA session regenerate error:', regenErr);
        return res.status(500).json({ error: 'Something went wrong logging you in.' });
      }

      req.session.staff = {
        id: staffMember.id,
        fullName: staffMember.full_name,
        username: staffMember.username,
        role: staffMember.role,
        canEditPrices: staffMember.can_edit_prices,
        departmentId: staffMember.department_id,
        mustChangePassword: staffMember.must_change_password
      };

      supabase
        .from('staff')
        .update({ last_seen: new Date().toISOString() })
        .eq('id', staffMember.id)
        .then(() => {
          res.json({ success: true, staff: req.session.staff });
        });
    });
  } catch (err) {
    console.error('Login MFA unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging you in.' });
  }
});

router.post('/logout', (req, res) => {
  try {
    req.session.destroy((err) => {
      if (err) {
        console.error('Logout session destroy error:', err);
        return res.status(500).json({ error: 'Could not log out. Try again.' });
      }
      res.clearCookie('connect.sid');
      res.json({ success: true });
    });
  } catch (err) {
    console.error('Logout unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging out.' });
  }
});

// GET /api/accounting/auth/me — used by frontend to check if a session is active
router.get('/me', (req, res) => {
  if (!req.session.staff) {
    return res.status(401).json({ error: 'Not logged in.' });
  }
  res.json({ staff: req.session.staff });
});

module.exports = router;

