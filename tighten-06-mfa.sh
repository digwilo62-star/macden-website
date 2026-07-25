#!/usr/bin/env bash
# TIGHTENING BATCH 6: Optional two-factor authentication (TOTP, like
# Google Authenticator). Opt-in per person via Settings - nobody is
# forced into it. Thoroughly tested: real secret/token round-trip
# verified, and confirmed the auth middleware genuinely blocks access
# during the pending-MFA window (password correct but code not yet
# entered) before shipping this.
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

cat > server/package.json << 'EOF_SERVER_PACKAGE_JSON'
{
  "name": "macden-accounting-server",
  "version": "1.0.0",
  "description": "Backend for MACDEN Accounting Department tool",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "create-staff": "node scripts/createStaff.js"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.0",
    "bcrypt": "^6.0.0",
    "connect-pg-simple": "^9.0.1",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.19.2",
    "express-rate-limit": "^7.4.0",
    "express-session": "^1.18.0",
    "helmet": "^7.2.0",
    "multer": "^1.4.5-lts.1",
    "nodemailer": "^9.0.3",
    "otplib": "^12.0.1",
    "pg": "^8.13.0"
  }
}

EOF_SERVER_PACKAGE_JSON

cat > server/routes/auth.js << 'EOF_SERVER_ROUTES_AUTH_JS'
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

EOF_SERVER_ROUTES_AUTH_JS

cat > server/routes/settings.js << 'EOF_SERVER_ROUTES_SETTINGS_JS'
const express = require('express');
const bcrypt = require('bcrypt');
const { authenticator } = require('otplib');
const supabase = require('../config/supabaseClient');
const pgPool = require('../config/pgPool');

const router = express.Router();

// GET /api/accounting/settings/me — full profile for the Settings page
router.get('/me', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, username, email, role, bio, created_at, departments(name), notify_email_broadcasts, notify_email_messages, notify_desktop, mfa_enabled')
      .eq('id', req.session.staff.id)
      .single();

    if (error) {
      console.error('Settings fetch error:', error);
      return res.status(500).json({ error: 'Could not load your profile.' });
    }

    res.json({
      profile: {
        fullName: data.full_name,
        username: data.username,
        email: data.email,
        role: data.role,
        department: data.departments ? data.departments.name : null,
        bio: data.bio,
        dateJoined: data.created_at,
        notifyEmailBroadcasts: data.notify_email_broadcasts,
        notifyEmailMessages: data.notify_email_messages,
        notifyDesktop: data.notify_desktop,
        mfaEnabled: data.mfa_enabled
      }
    });
  } catch (err) {
    console.error('Settings fetch unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your profile.' });
  }
});

// PUT /api/accounting/settings/profile — only bio is editable by the staff member themselves
router.put('/profile', async (req, res) => {
  try {
    const { bio } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({ bio: bio || null })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update your profile.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Profile update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating your profile.' });
  }
});

// PUT /api/accounting/settings/notifications
router.put('/notifications', async (req, res) => {
  try {
    const { notifyEmailBroadcasts, notifyEmailMessages, notifyDesktop } = req.body;

    const { error } = await supabase
      .from('staff')
      .update({
        notify_email_broadcasts: !!notifyEmailBroadcasts,
        notify_email_messages: !!notifyEmailMessages,
        notify_desktop: !!notifyDesktop
      })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not update notification preferences.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Notifications update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// PUT /api/accounting/settings/password — real password change
router.put('/password', async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'Current and new password are required.' });
    }
    if (newPassword.length < 8) {
      return res.status(400).json({ error: 'New password must be at least 8 characters.' });
    }

    const { data: staffMember, error: fetchError } = await supabase
      .from('staff')
      .select('password_hash')
      .eq('id', req.session.staff.id)
      .single();

    if (fetchError || !staffMember) {
      return res.status(500).json({ error: 'Could not verify your account.' });
    }

    const matches = await bcrypt.compare(currentPassword, staffMember.password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Current password is incorrect.' });
    }

    const newHash = await bcrypt.hash(newPassword, 10);
    const { error: updateError } = await supabase
      .from('staff')
      .update({ password_hash: newHash, must_change_password: false })
      .eq('id', req.session.staff.id);

    if (updateError) {
      return res.status(500).json({ error: 'Could not update your password.' });
    }

    // Clear the forced-change flag in the session too, so the frontend
    // stops redirecting immediately without needing a fresh login.
    req.session.staff.mustChangePassword = false;

    res.json({ success: true });
  } catch (err) {
    console.error('Password change unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong changing your password.' });
  }
});

// POST /api/accounting/settings/logout-all-devices
// Deletes every session row belonging to this person from the Postgres
// session store, forcing every logged-in device/browser to be signed out.
// Their CURRENT session is deleted too, so they'll need to log back in here as well.
router.post('/logout-all-devices', async (req, res) => {
  try {
    const staffId = req.session.staff.id;

    await pgPool.query(
      `DELETE FROM user_sessions WHERE sess::jsonb -> 'staff' ->> 'id' = $1`,
      [staffId]
    );

    res.json({ success: true });
  } catch (err) {
    console.error('Logout-all-devices unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong logging out other devices.' });
  }
});

// POST /api/accounting/settings/mfa/setup — generates a new secret, not
// active yet until confirmed with a real code via /mfa/verify
router.post('/mfa/setup', async (req, res) => {
  try {
    const secret = authenticator.generateSecret();
    const uri = authenticator.keyuri(req.session.staff.username, 'MACDEN Portal', secret);

    // Store the pending secret temporarily in the session (not the DB yet) —
    // it only becomes permanent once they prove they can generate a valid
    // code from it in the next step. Prevents someone locking themselves
    // out with a secret they never actually saved into their app.
    req.session.pendingMfaSecret = secret;

    res.json({ secret, uri });
  } catch (err) {
    console.error('MFA setup unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong setting up two-factor authentication.' });
  }
});

// POST /api/accounting/settings/mfa/verify — confirms setup with a real code
router.post('/mfa/verify', async (req, res) => {
  try {
    const { code } = req.body;
    const pendingSecret = req.session.pendingMfaSecret;

    if (!pendingSecret) {
      return res.status(400).json({ error: 'Start MFA setup again first.' });
    }
    if (!code) {
      return res.status(400).json({ error: 'Enter the 6-digit code from your authenticator app.' });
    }

    const isValid = authenticator.verify({ token: code, secret: pendingSecret });
    if (!isValid) {
      return res.status(400).json({ error: 'Incorrect code. Check your authenticator app and try again.' });
    }

    const { error } = await supabase
      .from('staff')
      .update({ mfa_secret: pendingSecret, mfa_enabled: true })
      .eq('id', req.session.staff.id);

    if (error) {
      console.error('MFA enable error:', error);
      return res.status(500).json({ error: 'Could not enable two-factor authentication.' });
    }

    delete req.session.pendingMfaSecret;
    res.json({ success: true });
  } catch (err) {
    console.error('MFA verify unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong confirming two-factor authentication.' });
  }
});

// POST /api/accounting/settings/mfa/disable — requires current password
router.post('/mfa/disable', async (req, res) => {
  try {
    const { currentPassword } = req.body;
    if (!currentPassword) {
      return res.status(400).json({ error: 'Enter your current password to disable two-factor authentication.' });
    }

    const { data: staffMember } = await supabase
      .from('staff')
      .select('password_hash')
      .eq('id', req.session.staff.id)
      .single();

    const matches = await bcrypt.compare(currentPassword, staffMember.password_hash);
    if (!matches) {
      return res.status(401).json({ error: 'Incorrect password.' });
    }

    const { error } = await supabase
      .from('staff')
      .update({ mfa_secret: null, mfa_enabled: false })
      .eq('id', req.session.staff.id);

    if (error) {
      return res.status(500).json({ error: 'Could not disable two-factor authentication.' });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('MFA disable unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

EOF_SERVER_ROUTES_SETTINGS_JS

cat > accounting/login.html << 'EOF_ACCOUNTING_LOGIN_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Sign In — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
</head>
<body>
  <div class="login-shell">
    <div class="login-brand-panel">
      <div class="login-brand-logo">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <div>
          <span>MACDEN</span>
          <small>COMMUNICATIONS</small>
        </div>
      </div>
      <div class="login-tagline">
        Stronger Together.<br>
        <span class="gold">Better Every Day.</span>
      </div>
    </div>

    <div class="login-form-panel">
      <div class="login-form-inner">
        <h1>Welcome Back</h1>
        <p class="login-form-subtitle">Sign in to your account</p>

        <div id="alert" class="alert alert-error"></div>

        <form id="loginForm">
          <div class="field">
            <label for="email">Email</label>
            <input type="text" id="email" name="email" placeholder="name@macden.com" required>
          </div>
          <div class="field">
            <label for="password">Password</label>
            <input type="password" id="password" name="password" placeholder="••••••••" required>
          </div>
          <div class="login-row-between">
            <label><input type="checkbox" id="rememberMe"> Remember me</label>
            <a href="#">Forgot password?</a>
          </div>
          <button type="submit" class="btn btn-primary" id="submitBtn">Sign In</button>
        </form>

        <form id="mfaForm" style="display:none;">
          <p style="font-size:13px; color:var(--text-secondary); margin-bottom:18px;">Enter the 6-digit code from your authenticator app.</p>
          <div class="field">
            <label for="mfaCode">Authentication Code</label>
            <input type="text" id="mfaCode" placeholder="000000" maxlength="6" inputmode="numeric" autocomplete="one-time-code" required>
          </div>
          <button type="submit" class="btn btn-primary" id="mfaSubmitBtn">Verify</button>
        </form>

        <p class="login-footer-link">Need help? Contact IT Support</p>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    const form = document.getElementById('loginForm');
    const alertEl = document.getElementById('alert');
    const submitBtn = document.getElementById('submitBtn');

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert(alertEl);
      submitBtn.disabled = true;
      submitBtn.textContent = 'Signing in…';

      try {
        const result = await apiRequest('/auth/login', {
          method: 'POST',
          body: {
            username: document.getElementById('email').value.trim(),
            password: document.getElementById('password').value
          }
        });

        if (result.requiresMfa) {
          form.style.display = 'none';
          document.getElementById('mfaForm').style.display = 'block';
          document.getElementById('mfaCode').focus();
          return;
        }

        if (result.staff.mustChangePassword) {
          window.location.href = 'settings.html?forcePasswordChange=1';
        } else {
          window.location.href = 'dashboard.html';
        }
      } catch (err) {
        showAlert(alertEl, err.message);
        submitBtn.disabled = false;
        submitBtn.textContent = 'Sign In';
      }
    });

    const mfaForm = document.getElementById('mfaForm');
    const mfaSubmitBtn = document.getElementById('mfaSubmitBtn');

    mfaForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      hideAlert(alertEl);
      mfaSubmitBtn.disabled = true;
      mfaSubmitBtn.textContent = 'Verifying…';

      try {
        const result = await apiRequest('/auth/login-mfa', {
          method: 'POST',
          body: { code: document.getElementById('mfaCode').value.trim() }
        });

        if (result.staff.mustChangePassword) {
          window.location.href = 'settings.html?forcePasswordChange=1';
        } else {
          window.location.href = 'dashboard.html';
        }
      } catch (err) {
        showAlert(alertEl, err.message);
        mfaSubmitBtn.disabled = false;
        mfaSubmitBtn.textContent = 'Verify';
      }
    });
  </script>
</body>
</html>

EOF_ACCOUNTING_LOGIN_HTML

cat > accounting/settings.html << 'EOF_ACCOUNTING_SETTINGS_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Settings — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .set-panel { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 24px; margin-bottom: 20px; max-width: 640px; }
    .set-panel h2 { font-size: 15px; margin-bottom: 4px; }
    .set-panel .sub { font-size: 12.5px; color: var(--text-secondary); margin-bottom: 18px; }

    .set-avatar-row { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; }
    .set-avatar { width: 64px; height: 64px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 22px; font-weight: 700; }

    .set-field-row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
    .set-field-row:last-child { border-bottom: none; }
    .set-field-label { color: var(--text-secondary); }
    .set-field-value { color: var(--text-primary); font-weight: 500; }

    .set-locked-note { background: var(--gold-dim); color: #8a6d00; padding: 10px 14px; border-radius: var(--radius-sm); font-size: 12px; margin-top: 14px; }

    .set-toggle-row { display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid var(--border); }
    .set-toggle-row:last-child { border-bottom: none; }
    .set-toggle-row .label { font-size: 13px; font-weight: 500; color: var(--text-primary); }
    .set-toggle-row .desc { font-size: 11.5px; color: var(--text-muted); }
    .set-toggle { position: relative; width: 40px; height: 22px; border-radius: 999px; border: none; cursor: pointer; background: var(--border); flex-shrink: 0; }
    .set-toggle.on { background: var(--primary); }
    .set-toggle .knob { position: absolute; top: 2px; left: 2px; width: 18px; height: 18px; border-radius: 50%; background: #fff; transition: left 0.15s ease; }
    .set-toggle.on .knob { left: 20px; }

    .set-appearance-row { display: flex; gap: 10px; }
    .set-appearance-btn { flex: 1; padding: 12px; border-radius: var(--radius-sm); border: 1.5px solid var(--border); text-align: center; font-size: 12.5px; font-weight: 600; cursor: pointer; background: var(--surface); color: var(--text-primary); }
    .set-appearance-btn.active { border-color: var(--primary); background: var(--primary-dim); color: var(--primary); }
    .set-appearance-btn.disabled { opacity: 0.5; cursor: not-allowed; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN</span>
      </div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link active"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <a href="help.html" class="sidebar-link" style="margin-bottom:6px;"><i class="ti ti-help-circle"></i> Help</a>
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <div class="notif-wrap">
          <button class="topbar-bell" id="notifBell" aria-label="Notifications"><i class="ti ti-bell"></i><span class="dot" id="notifDot" style="display:none;">0</span></button>
          <div class="notif-dropdown" id="notifDropdown"></div>
        </div>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Settings</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div id="forceChangeBanner" class="set-locked-note" style="display:none; max-width:640px; margin-bottom:20px;">
          <i class="ti ti-alert-triangle"></i> Your account was just created by HR — please set a new password below before continuing.
        </div>

        <!-- Profile -->
        <div class="set-panel">
          <h2>Profile</h2>
          <p class="sub">View and update your personal information.</p>

          <div class="set-avatar-row">
            <div class="set-avatar" id="profileAvatar">—</div>
            <div>
              <div style="font-weight:700; font-size:15px;" id="profileName">—</div>
              <div style="font-size:12.5px; color:var(--text-secondary);" id="profileRoleDept">—</div>
            </div>
          </div>

          <div class="set-field-row"><span class="set-field-label">Username</span><span class="set-field-value" id="profileUsername">—</span></div>
          <div class="set-field-row"><span class="set-field-label">Email</span><span class="set-field-value" id="profileEmail">—</span></div>
          <div class="set-field-row"><span class="set-field-label">Date Joined</span><span class="set-field-value" id="profileDate">—</span></div>

          <div class="set-locked-note"><i class="ti ti-info-circle"></i> Your name, role, department, and join date are managed by HR and can't be changed here.</div>

          <div style="margin-top:16px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Status / Bio</label>
            <textarea id="bioInput" placeholder="A short status or bio…" style="width:100%; min-height:70px; background:var(--surface-raised); border:1px solid var(--border); border-radius:var(--radius-sm); padding:10px 12px; font-size:13px; font-family:var(--font-body); color:var(--text-primary); resize:vertical;"></textarea>
            <div id="profileAlert" class="alert alert-error" style="margin-top:10px;"></div>
            <button class="btn btn-primary" id="saveBioBtn" style="width:auto; padding:9px 20px; margin-top:10px;">Save</button>
          </div>
        </div>

        <!-- Notifications -->
        <div class="set-panel">
          <h2>Notifications</h2>
          <p class="sub">Choose how and when you want to be notified.</p>
          <div class="set-toggle-row">
            <div><div class="label">Email me for new broadcasts</div><div class="desc">Receive an email when a new broadcast is sent.</div></div>
            <button class="set-toggle" id="toggleBroadcasts" onclick="toggleSwitch(this)"><span class="knob"></span></button>
          </div>
          <div class="set-toggle-row">
            <div><div class="label">Email me for direct messages</div><div class="desc">Receive an email when someone sends you a message.</div></div>
            <button class="set-toggle" id="toggleMessages" onclick="toggleSwitch(this)"><span class="knob"></span></button>
          </div>
          <div class="set-toggle-row">
            <div><div class="label">Desktop notifications</div><div class="desc">Show desktop notifications for new activity.</div></div>
            <button class="set-toggle" id="toggleDesktop" onclick="toggleSwitch(this)"><span class="knob"></span></button>
          </div>
          <div class="set-locked-note" style="margin-top:14px;"><i class="ti ti-check"></i> These preferences are fully active — turn any of them off if you don't want that email.</div>
        </div>

        <!-- Security -->
        <div class="set-panel">
          <h2>Security</h2>
          <p class="sub">Keep your account secure.</p>
          <div id="passwordAlert" class="alert alert-error"></div>
          <div id="passwordSuccess" class="alert alert-success"></div>
          <div style="margin-bottom:12px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Current Password</label>
            <input type="password" id="currentPassword" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          </div>
          <div style="margin-bottom:12px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">New Password</label>
            <input type="password" id="newPassword" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          </div>
          <div style="margin-bottom:16px;">
            <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Confirm New Password</label>
            <input type="password" id="confirmPassword" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body);">
          </div>
          <button class="btn btn-primary" id="changePasswordBtn" style="width:auto; padding:9px 20px;">Update Password</button>

          <div style="margin-top:20px; padding-top:20px; border-top:1px solid var(--border);">
            <p style="font-size:12.5px; color:var(--text-secondary); margin-bottom:10px;">Signed in somewhere you don't recognize? Sign out everywhere at once.</p>
            <button class="btn btn-ghost" id="logoutAllBtn" style="width:auto; padding:9px 20px; color:var(--error); border-color:var(--error);">Log out of all devices</button>
          </div>

          <div style="margin-top:20px; padding-top:20px; border-top:1px solid var(--border);">
            <h3 style="font-size:13.5px; margin-bottom:4px;">Two-Factor Authentication</h3>
            <p style="font-size:12.5px; color:var(--text-secondary); margin-bottom:12px;">Add an extra layer of security using an authenticator app (Google Authenticator, Authy, etc).</p>

            <div id="mfaStatusOff">
              <button class="btn btn-primary" id="mfaEnableBtn" style="width:auto; padding:9px 20px;">Enable Two-Factor Authentication</button>
            </div>

            <div id="mfaStatusOn" style="display:none;">
              <div class="set-locked-note" style="display:inline-flex; align-items:center; gap:6px;"><i class="ti ti-shield-check"></i> Two-factor authentication is ON</div>
              <div style="margin-top:12px;">
                <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Current Password (to disable)</label>
                <input type="password" id="mfaDisablePassword" style="width:100%; max-width:280px; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); margin-bottom:10px;">
                <br>
                <button class="btn btn-ghost" id="mfaDisableBtn" style="width:auto; padding:9px 20px; color:var(--error); border-color:var(--error);">Disable Two-Factor Authentication</button>
              </div>
            </div>

            <div id="mfaSetupFlow" style="display:none; margin-top:14px;">
              <div id="mfaSetupAlert" class="alert alert-error"></div>
              <p style="font-size:12.5px; color:var(--text-secondary);">1. Open your authenticator app and add a new account manually using this key:</p>
              <div style="background:var(--surface-raised); border:1px solid var(--border); border-radius:var(--radius-sm); padding:12px 14px; font-family:var(--font-mono); font-size:14px; letter-spacing:1px; margin:8px 0; word-break:break-all;" id="mfaSecretDisplay"></div>
              <p style="font-size:12.5px; color:var(--text-secondary); margin-top:14px;">2. Enter the 6-digit code your app generates:</p>
              <input type="text" id="mfaVerifyCode" placeholder="000000" maxlength="6" inputmode="numeric" style="width:140px; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); margin:6px 0 12px;">
              <br>
              <button class="btn btn-primary" id="mfaVerifyBtn" style="width:auto; padding:9px 20px;">Confirm &amp; Enable</button>
              <button class="btn btn-ghost" id="mfaCancelBtn" style="width:auto; padding:9px 20px; margin-left:8px;">Cancel</button>
            </div>
          </div>
        </div>

        <!-- Appearance -->
        <div class="set-panel">
          <h2>Appearance</h2>
          <p class="sub">Customize how the app looks.</p>
          <div class="set-appearance-row">
            <div class="set-appearance-btn active"><i class="ti ti-sun"></i> Light</div>
            <div class="set-appearance-btn disabled" title="Coming soon"><i class="ti ti-moon"></i> Dark (coming soon)</div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/notifications.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    function initials(name) {
      if (!name) return '?';
      return name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
    }

    function toggleSwitch(btn) {
      btn.classList.toggle('on');
    }

    async function init() {
      const params = new URLSearchParams(window.location.search);
      if (params.get('forcePasswordChange') === '1') {
        document.getElementById('forceChangeBanner').style.display = 'block';
        setTimeout(() => document.getElementById('currentPassword').scrollIntoView({ behavior: 'smooth', block: 'center' }), 300);
      }

      try {
        const result = await apiRequest('/settings/me');
        const p = result.profile;

        document.getElementById('profileAvatar').textContent = initials(p.fullName);
        document.getElementById('profileName').textContent = p.fullName;
        document.getElementById('profileRoleDept').textContent = p.role + (p.department ? ' · ' + p.department : '');
        document.getElementById('profileUsername').textContent = p.username;
        document.getElementById('profileEmail').textContent = p.email;
        document.getElementById('profileDate').textContent = new Date(p.dateJoined).toLocaleDateString();
        document.getElementById('bioInput').value = p.bio || '';

        if (p.mfaEnabled) {
          document.getElementById('mfaStatusOff').style.display = 'none';
          document.getElementById('mfaStatusOn').style.display = 'block';
        }

        if (p.notifyEmailBroadcasts) document.getElementById('toggleBroadcasts').classList.add('on');
        if (p.notifyEmailMessages) document.getElementById('toggleMessages').classList.add('on');
        if (p.notifyDesktop) document.getElementById('toggleDesktop').classList.add('on');
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
    }

    document.getElementById('saveBioBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('profileAlert');
      hideAlert(alertEl);
      try {
        await apiRequest('/settings/profile', { method: 'PUT', body: { bio: document.getElementById('bioInput').value.trim() } });
      } catch (err) {
        showAlert(alertEl, err.message);
      }
    });

    ['toggleBroadcasts', 'toggleMessages', 'toggleDesktop'].forEach(id => {
      document.getElementById(id).addEventListener('click', async () => {
        try {
          await apiRequest('/settings/notifications', {
            method: 'PUT',
            body: {
              notifyEmailBroadcasts: document.getElementById('toggleBroadcasts').classList.contains('on'),
              notifyEmailMessages: document.getElementById('toggleMessages').classList.contains('on'),
              notifyDesktop: document.getElementById('toggleDesktop').classList.contains('on')
            }
          });
        } catch (err) {
          alert(err.message);
        }
      });
    });

    document.getElementById('changePasswordBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('passwordAlert');
      const successEl = document.getElementById('passwordSuccess');
      hideAlert(alertEl);
      hideAlert(successEl);

      const currentPassword = document.getElementById('currentPassword').value;
      const newPassword = document.getElementById('newPassword').value;
      const confirmPassword = document.getElementById('confirmPassword').value;

      if (newPassword !== confirmPassword) {
        showAlert(alertEl, 'New password and confirmation do not match.');
        return;
      }

      const btn = document.getElementById('changePasswordBtn');
      btn.disabled = true;

      try {
        await apiRequest('/settings/password', { method: 'PUT', body: { currentPassword, newPassword } });
        showAlert(successEl, 'Password updated successfully.', 'success');
        document.getElementById('currentPassword').value = '';
        document.getElementById('newPassword').value = '';
        document.getElementById('confirmPassword').value = '';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
      }
    });

    document.getElementById('logoutAllBtn').addEventListener('click', async () => {
      if (!confirm('This will sign you out on every device, including this one. Continue?')) return;
      try {
        await apiRequest('/settings/logout-all-devices', { method: 'POST' });
      } catch (err) {
        // Even if this errors, the safest move is still to send them to login
      }
      window.location.href = 'login.html';
    });

    document.getElementById('mfaEnableBtn').addEventListener('click', async () => {
      try {
        const result = await apiRequest('/settings/mfa/setup', { method: 'POST' });
        document.getElementById('mfaSecretDisplay').textContent = result.secret;
        document.getElementById('mfaStatusOff').style.display = 'none';
        document.getElementById('mfaSetupFlow').style.display = 'block';
      } catch (err) {
        alert(err.message);
      }
    });

    document.getElementById('mfaCancelBtn').addEventListener('click', () => {
      document.getElementById('mfaSetupFlow').style.display = 'none';
      document.getElementById('mfaStatusOff').style.display = 'block';
      document.getElementById('mfaVerifyCode').value = '';
    });

    document.getElementById('mfaVerifyBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('mfaSetupAlert');
      hideAlert(alertEl);
      const btn = document.getElementById('mfaVerifyBtn');
      btn.disabled = true;

      try {
        await apiRequest('/settings/mfa/verify', {
          method: 'POST',
          body: { code: document.getElementById('mfaVerifyCode').value.trim() }
        });
        document.getElementById('mfaSetupFlow').style.display = 'none';
        document.getElementById('mfaStatusOn').style.display = 'block';
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
      }
    });

    document.getElementById('mfaDisableBtn').addEventListener('click', async () => {
      const password = document.getElementById('mfaDisablePassword').value;
      if (!password) { alert('Enter your current password.'); return; }
      if (!confirm('Disable two-factor authentication on your account?')) return;

      try {
        await apiRequest('/settings/mfa/disable', {
          method: 'POST',
          body: { currentPassword: password }
        });
        document.getElementById('mfaStatusOn').style.display = 'none';
        document.getElementById('mfaStatusOff').style.display = 'block';
        document.getElementById('mfaDisablePassword').value = '';
      } catch (err) {
        alert(err.message);
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_SETTINGS_HTML

echo "Tightening batch 6 complete: MFA added. 19 of 40 items now done."
echo "Run npm install in server/ to get the new otplib dependency."