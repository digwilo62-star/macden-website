#!/usr/bin/env bash
# Replaces the accounting login page with the new company-wide portal design
# (screen 1 of 15 mockups). Login now accepts email OR username.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting/assets

cat > server/routes/auth.js << 'EOF_SERVER_ROUTES_AUTH_JS'
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

EOF_SERVER_ROUTES_AUTH_JS

cat > accounting/assets/portal-style.css << 'EOF_ACCOUNTING_ASSETS_PORTAL-STYLE_CSS'
/* ============================================================
   MACDEN Portal — Design Tokens
   Matches the confirmed mockup direction: deep green primary,
   gold accent, Montserrat headings + Inter body.
   Desktop-first, company-wide (not accounting-only).
   ============================================================ */

@import url('https://fonts.googleapis.com/css2?family=Montserrat:wght@600;700;800&family=Inter:wght@400;500;600;700&display=swap');

:root {
  --primary: #0d5c2f;
  --primary-light: #1e7a3e;
  --primary-dim: rgba(13, 92, 47, 0.08);
  --gold: #f2c94c;
  --gold-dim: rgba(242, 201, 76, 0.15);

  --bg: #f7f8fa;
  --surface: #ffffff;
  --surface-raised: #f2f3f5;
  --border: #e5e7eb;
  --border-hover: #d1d5db;

  --text-primary: #2b2d31;
  --text-secondary: #6b7280;
  --text-muted: #9ca3af;

  --success: #1e7a3e;
  --success-dim: rgba(30, 122, 62, 0.1);
  --warning: #f2c94c;
  --warning-dim: rgba(242, 201, 76, 0.15);
  --error: #dc2626;
  --error-dim: rgba(220, 38, 38, 0.08);

  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 16px;

  --font-heading: 'Montserrat', -apple-system, sans-serif;
  --font-body: 'Inter', -apple-system, sans-serif;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--text-primary);
  font-family: var(--font-body);
  font-size: 14px;
  line-height: 1.5;
  min-width: 1024px; /* desktop-first */
}

h1, h2, h3 { font-family: var(--font-heading); font-weight: 700; margin: 0; }

/* ---------- Split-panel login shell ---------- */

.login-shell {
  min-height: 100vh;
  display: flex;
}

.login-brand-panel {
  width: 42%;
  background: var(--primary);
  background-image:
    radial-gradient(circle at 15% 85%, rgba(255,255,255,0.06), transparent 45%),
    radial-gradient(circle at 85% 15%, rgba(242,201,76,0.10), transparent 40%);
  color: #ffffff;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 60px 56px;
  position: relative;
  overflow: hidden;
}

.login-brand-panel::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, rgba(0,0,0,0) 60%, rgba(0,0,0,0.25) 100%);
  pointer-events: none;
}

.login-brand-logo {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 48px;
}

.login-brand-logo img {
  width: 44px;
  height: 44px;
  border-radius: 10px;
  object-fit: cover;
  background: #fff;
}

.login-brand-logo span {
  font-family: var(--font-heading);
  font-weight: 800;
  font-size: 18px;
  letter-spacing: 0.02em;
}

.login-brand-logo small {
  display: block;
  font-family: var(--font-body);
  font-weight: 500;
  font-size: 10.5px;
  letter-spacing: 0.08em;
  opacity: 0.75;
  margin-top: 1px;
}

.login-tagline {
  font-size: 32px;
  font-weight: 800;
  line-height: 1.25;
  max-width: 340px;
  position: relative;
  z-index: 1;
}

.login-tagline .gold { color: var(--gold); }

/* ---------- Right side form panel ---------- */

.login-form-panel {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface);
  padding: 40px;
}

.login-form-inner { width: 100%; max-width: 380px; }

.login-form-inner h1 {
  font-size: 26px;
  margin-bottom: 6px;
}

.login-form-subtitle {
  color: var(--text-secondary);
  font-size: 13.5px;
  margin-bottom: 32px;
}

.field { margin-bottom: 18px; }

.field label {
  display: block;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--text-primary);
  margin-bottom: 7px;
}

.field input {
  width: 100%;
  background: var(--surface);
  border: 1.5px solid var(--border);
  border-radius: var(--radius-sm);
  padding: 11px 14px;
  color: var(--text-primary);
  font-size: 13.5px;
  font-family: var(--font-body);
  transition: border-color 0.15s ease;
}

.field input:focus {
  outline: none;
  border-color: var(--primary);
}

.field input::placeholder { color: var(--text-muted); }

.login-row-between {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
  font-size: 12.5px;
}

.login-row-between label {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--text-secondary);
  cursor: pointer;
}

.login-row-between a {
  color: var(--primary);
  text-decoration: none;
  font-weight: 600;
}

.btn {
  width: 100%;
  padding: 12px 16px;
  border-radius: var(--radius-sm);
  border: none;
  font-size: 14px;
  font-weight: 700;
  font-family: var(--font-body);
  cursor: pointer;
  transition: background 0.15s ease, opacity 0.15s ease;
}

.btn-primary { background: var(--primary); color: #ffffff; }
.btn-primary:hover { background: var(--primary-light); }
.btn-primary:disabled { opacity: 0.55; cursor: not-allowed; }

.login-footer-link {
  text-align: center;
  margin-top: 24px;
  font-size: 12.5px;
  color: var(--text-muted);
}

.login-footer-link a { color: var(--primary); text-decoration: none; font-weight: 600; }

/* ---------- Alerts ---------- */

.alert {
  padding: 11px 14px;
  border-radius: var(--radius-sm);
  font-size: 12.5px;
  margin-bottom: 18px;
  display: none;
}

.alert-error { background: var(--error-dim); color: var(--error); border: 1px solid rgba(220,38,38,0.2); }
.alert-success { background: var(--success-dim); color: var(--success); border: 1px solid rgba(30,122,62,0.2); }
.alert.visible { display: block; }

EOF_ACCOUNTING_ASSETS_PORTAL-STYLE_CSS

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
        await apiRequest('/auth/login', {
          method: 'POST',
          body: {
            username: document.getElementById('email').value.trim(),
            password: document.getElementById('password').value
          }
        });
        window.location.href = 'dashboard.html';
      } catch (err) {
        showAlert(alertEl, err.message);
        submitBtn.disabled = false;
        submitBtn.textContent = 'Sign In';
      }
    });
  </script>
</body>
</html>

EOF_ACCOUNTING_LOGIN_HTML

echo "New portal login page installed (screen 1 of 15)."
echo "Restart your server (Ctrl+C then npm start) to test locally."