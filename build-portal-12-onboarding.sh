#!/usr/bin/env bash
# Adds the full onboarding wizard (3 steps, HR-initiated account creation
# with real NIN/address/phone/branch fields, welcome email with login
# credentials) and HR's Manage Staff admin view (edit status, deactivate,
# reactivate). Admin-only.
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes server/utils accounting

cat > server/routes/admin.js << 'EOF_SERVER_ROUTES_ADMIN_JS'
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

EOF_SERVER_ROUTES_ADMIN_JS

cat > server/utils/email.js << 'EOF_SERVER_UTILS_EMAIL_JS'
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: process.env.SMTP_PORT,
  secure: process.env.SMTP_PORT === '465', // true for port 465, false for 587/others
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  }
});

async function sendVerificationEmail(toEmail, fullName, code) {
  await transporter.sendMail({
    from: process.env.SMTP_FROM || '"MACDEN Accounting" <no-reply@macden.com.ng>',
    to: toEmail,
    subject: 'Verify your MACDEN Accounting account',
    text: `Hi ${fullName},\n\nYour verification code is: ${code}\n\nThis code expires in 15 minutes.\n\nAfter verifying, your account will still need admin approval before you can log in.`,
    html: `
      <p>Hi ${fullName},</p>
      <p>Your verification code is:</p>
      <p style="font-size: 24px; font-weight: bold; letter-spacing: 4px;">${code}</p>
      <p>This code expires in 15 minutes.</p>
      <p>After verifying, your account will still need admin approval before you can log in.</p>
    `
  });
}

async function sendWelcomeEmail(toEmail, fullName, username, tempPassword) {
  await transporter.sendMail({
    from: process.env.SMTP_FROM || '"MACDEN Accounting" <no-reply@macden.com.ng>',
    to: toEmail,
    subject: 'Welcome to MACDEN — Your account is ready',
    text: `Hi ${fullName},\n\nHR has created your MACDEN portal account.\n\nUsername: ${username}\nTemporary password: ${tempPassword}\n\nPlease log in and change your password as soon as possible from Settings.`,
    html: `
      <p>Hi ${fullName},</p>
      <p>HR has created your MACDEN portal account.</p>
      <p><strong>Username:</strong> ${username}<br>
      <strong>Temporary password:</strong> ${tempPassword}</p>
      <p>Please log in and change your password as soon as possible from Settings.</p>
    `
  });
}

module.exports = { sendVerificationEmail, sendWelcomeEmail };

EOF_SERVER_UTILS_EMAIL_JS

cat > accounting/onboard.html << 'EOF_ACCOUNTING_ONBOARD_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Add New Staff — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .step-indicator { display: flex; align-items: center; gap: 10px; margin-bottom: 24px; }
    .step-item { display: flex; align-items: center; gap: 8px; font-size: 12.5px; color: var(--text-muted); }
    .step-item.active, .step-item.done { color: var(--text-primary); font-weight: 600; }
    .step-num { width: 22px; height: 22px; border-radius: 50%; background: var(--border); color: var(--text-muted); display: flex; align-items: center; justify-content: center; font-size: 11px; font-weight: 700; }
    .step-item.active .step-num { background: var(--primary); color: #fff; }
    .step-item.done .step-num { background: var(--success); color: #fff; }
    .step-arrow { color: var(--border); }

    .onb-grid { display: grid; grid-template-columns: 1fr 260px; gap: 20px; }
    .onb-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); padding: 26px; }
    .onb-field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px; }
    .onb-field label { display: block; font-size: 12.5px; font-weight: 600; margin-bottom: 6px; }
    .onb-field input, .onb-field select, .onb-field textarea {
      width: 100%; background: var(--surface-raised); border: 1px solid var(--border); border-radius: var(--radius-sm);
      padding: 9px 12px; font-size: 13px; font-family: var(--font-body); color: var(--text-primary);
    }
    .onb-note { background: var(--gold-dim); color: #8a6d00; padding: 12px 16px; border-radius: var(--radius-sm); font-size: 12px; }

    .review-section { margin-bottom: 16px; }
    .review-section h4 { font-size: 12.5px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); margin-bottom: 8px; }
    .review-row { display: flex; justify-content: space-between; padding: 6px 0; font-size: 13px; border-bottom: 1px solid var(--border); }

    .search-results { position: absolute; top: 100%; left: 0; right: 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-sm); margin-top: 4px; max-height: 180px; overflow-y: auto; z-index: 5; display: none; box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
    .search-result-item { padding: 8px 12px; cursor: pointer; font-size: 12.5px; }
    .search-result-item:hover { background: var(--surface-raised); }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout"><button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button></div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <button class="topbar-bell"><i class="ti ti-bell"></i></button>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Add New Staff Member</h1>
        <p class="page-greeting-sub"><a href="manage-staff.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Manage Staff</a></p>

        <div class="step-indicator">
          <div class="step-item active" id="stepInd1"><span class="step-num">1</span> Personal Information</div>
          <span class="step-arrow">→</span>
          <div class="step-item" id="stepInd2"><span class="step-num">2</span> Work Information</div>
          <span class="step-arrow">→</span>
          <div class="step-item" id="stepInd3"><span class="step-num">3</span> Review &amp; Create</div>
        </div>

        <div id="alert" class="alert alert-error"></div>

        <!-- Step 1 -->
        <div id="step1" class="onb-grid">
          <div class="onb-card">
            <div class="onb-field-row">
              <div class="onb-field"><label>Full Name *</label><input type="text" id="fullName"></div>
              <div class="onb-field"><label>Email Address *</label><input type="text" id="email"></div>
            </div>
            <div class="onb-field-row">
              <div class="onb-field"><label>Phone Number</label><input type="text" id="phone"></div>
              <div class="onb-field"><label>NIN</label><input type="text" id="nin"></div>
            </div>
            <div class="onb-field"><label>Residential Address</label><textarea id="address" style="min-height:70px;"></textarea></div>
            <div style="text-align:right; margin-top:16px;"><button class="btn btn-primary" style="width:auto; padding:9px 22px;" onclick="goToStep(2)">Next: Work Information →</button></div>
          </div>
          <div class="onb-note"><i class="ti ti-info-circle"></i> Photo upload isn't supported yet — staff records don't have a photo field in the database yet.</div>
        </div>

        <!-- Step 2 -->
        <div id="step2" class="onb-grid" style="display:none;">
          <div class="onb-card">
            <div class="onb-field-row">
              <div class="onb-field"><label>Role / Job Title *</label><input type="text" id="role"></div>
              <div class="onb-field"><label>Department *</label><select id="departmentId"></select></div>
            </div>
            <div class="onb-field-row">
              <div class="onb-field"><label>Branch</label><input type="text" id="branch" placeholder="e.g. Ikeja Branch"></div>
              <div class="onb-field"><label>Date Started</label><input type="date" id="dateStarted"></div>
            </div>
            <div class="onb-field" style="position:relative;">
              <label>Reports To (Direct Manager)</label>
              <input type="text" id="reportsToSearch" placeholder="Search staff member…">
              <div class="search-results" id="reportsToResults"></div>
              <div id="reportsToSelected" style="margin-top:6px; font-size:12.5px; color:var(--primary); display:none;"></div>
            </div>
            <div style="display:flex; justify-content:space-between; margin-top:16px;">
              <button class="btn btn-ghost" style="width:auto; padding:9px 22px;" onclick="goToStep(1)">← Back</button>
              <button class="btn btn-primary" style="width:auto; padding:9px 22px;" onclick="goToStep(3)">Next: Review &amp; Create →</button>
            </div>
          </div>
          <div class="onb-note"><i class="ti ti-info-circle"></i> Branch is a free-text field for now — no managed branch list exists yet.</div>
        </div>

        <!-- Step 3 -->
        <div id="step3" style="display:none;">
          <div class="onb-card" style="max-width:640px;">
            <div class="review-section">
              <h4>Personal Information</h4>
              <div class="review-row"><span>Full Name</span><span id="rvName"></span></div>
              <div class="review-row"><span>Email</span><span id="rvEmail"></span></div>
              <div class="review-row"><span>Phone</span><span id="rvPhone"></span></div>
              <div class="review-row"><span>NIN</span><span id="rvNin"></span></div>
            </div>
            <div class="review-section">
              <h4>Work Information</h4>
              <div class="review-row"><span>Role</span><span id="rvRole"></span></div>
              <div class="review-row"><span>Department</span><span id="rvDept"></span></div>
              <div class="review-row"><span>Branch</span><span id="rvBranch"></span></div>
              <div class="review-row"><span>Reports To</span><span id="rvReportsTo"></span></div>
            </div>
            <div class="onb-note" style="margin-top:16px;"><i class="ti ti-mail"></i> The staff member will receive an email with their login credentials.</div>
            <div style="display:flex; justify-content:space-between; margin-top:16px;">
              <button class="btn btn-ghost" style="width:auto; padding:9px 22px;" onclick="goToStep(2)">← Back</button>
              <button class="btn btn-primary" id="createAccountBtn" style="width:auto; padding:9px 22px;">Create Account</button>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let selectedReportsTo = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();

      try {
        const result = await apiRequest('/admin/departments');
        document.getElementById('departmentId').innerHTML = result.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');
      } catch (err) {}
    }

    function goToStep(n) {
      [1,2,3].forEach(i => {
        document.getElementById('step' + i).style.display = i === n ? (i === 3 ? 'block' : 'grid') : 'none';
        const ind = document.getElementById('stepInd' + i);
        ind.classList.remove('active', 'done');
        if (i < n) ind.classList.add('done');
        if (i === n) ind.classList.add('active');
      });
      if (n === 3) populateReview();
    }

    function populateReview() {
      document.getElementById('rvName').textContent = document.getElementById('fullName').value;
      document.getElementById('rvEmail').textContent = document.getElementById('email').value;
      document.getElementById('rvPhone').textContent = document.getElementById('phone').value || '—';
      document.getElementById('rvNin').textContent = document.getElementById('nin').value || '—';
      document.getElementById('rvRole').textContent = document.getElementById('role').value;
      document.getElementById('rvDept').textContent = document.getElementById('departmentId').selectedOptions[0]?.textContent || '—';
      document.getElementById('rvBranch').textContent = document.getElementById('branch').value || '—';
      document.getElementById('rvReportsTo').textContent = selectedReportsTo ? selectedReportsTo.full_name : '—';
    }

    let searchTimeout = null;
    document.getElementById('reportsToSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      const q = e.target.value.trim();
      const results = document.getElementById('reportsToResults');
      if (!q) { results.style.display = 'none'; return; }
      searchTimeout = setTimeout(async () => {
        try {
          const result = await apiRequest('/staff?search=' + encodeURIComponent(q));
          results.innerHTML = result.staff.map(s => '<div class="search-result-item" onclick=\'selectReportsTo(' + JSON.stringify(s) + ')\'>' + s.full_name + ' · ' + (s.department || '') + '</div>').join('');
          results.style.display = 'block';
        } catch (err) {}
      }, 250);
    });

    function selectReportsTo(staff) {
      selectedReportsTo = staff;
      document.getElementById('reportsToSearch').value = '';
      document.getElementById('reportsToResults').style.display = 'none';
      const el = document.getElementById('reportsToSelected');
      el.textContent = '✓ ' + staff.full_name;
      el.style.display = 'block';
    }

    document.getElementById('createAccountBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('alert');
      hideAlert(alertEl);

      const fullName = document.getElementById('fullName').value.trim();
      const email = document.getElementById('email').value.trim();
      const role = document.getElementById('role').value.trim();
      const departmentId = document.getElementById('departmentId').value;

      if (!fullName || !email || !role || !departmentId) {
        showAlert(alertEl, 'Full name, email, role, and department are required.');
        goToStep(1);
        return;
      }

      const btn = document.getElementById('createAccountBtn');
      btn.disabled = true;
      btn.textContent = 'Creating…';

      try {
        const result = await apiRequest('/admin/onboard-staff', {
          method: 'POST',
          body: {
            fullName, email,
            phone: document.getElementById('phone').value.trim(),
            nin: document.getElementById('nin').value.trim(),
            address: document.getElementById('address').value.trim(),
            role,
            departmentId,
            branch: document.getElementById('branch').value.trim(),
            dateStarted: document.getElementById('dateStarted').value,
            reportsTo: selectedReportsTo ? selectedReportsTo.id : null
          }
        });

        if (result.warning) {
          alert(result.warning);
        }
        window.location.href = 'manage-staff.html';
      } catch (err) {
        showAlert(alertEl, err.message);
        btn.disabled = false;
        btn.textContent = 'Create Account';
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_ONBOARD_HTML

cat > accounting/manage-staff.html << 'EOF_ACCOUNTING_MANAGE-STAFF_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Manage Staff — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .ms-toolbar { display: flex; justify-content: space-between; align-items: center; margin-bottom: 18px; }
    .ms-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .ms-header-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px; gap: 12px; padding: 12px 18px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .ms-row { display: grid; grid-template-columns: 200px 130px 130px 1fr 90px 90px; gap: 12px; align-items: center; padding: 12px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
    .ms-row:last-child { border-bottom: none; }
    .ms-empty { padding: 50px 18px; text-align: center; color: var(--text-muted); font-size: 13px; }
    .ms-status { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; }
    .ms-status.active { background: var(--success-dim); color: var(--success); }
    .ms-status.inactive { background: var(--error-dim); color: var(--error); }
    .ms-action-btn { border: 1px solid var(--border); background: var(--surface); border-radius: var(--radius-sm); padding: 5px 11px; font-size: 11px; font-weight: 600; cursor: pointer; font-family: var(--font-body); color: var(--text-primary); }
    .ms-action-btn.reactivate { background: var(--success-dim); color: var(--success); border-color: transparent; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="inbox.html" class="sidebar-link"><i class="ti ti-mail"></i> Inbox <span class="badge" id="unreadBadge" style="display:none;">0</span></a>
        <a href="compose.html" class="sidebar-link"><i class="ti ti-pencil"></i> Compose</a>
        <a href="broadcasts.html" class="sidebar-link"><i class="ti ti-speakerphone"></i> Broadcasts</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout"><button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button></div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <button class="topbar-bell"><i class="ti ti-bell"></i></button>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <div class="ms-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size: 22px;">Manage Staff</h1>
            <p class="page-greeting-sub" style="margin:0;"><a href="directory.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to Directory</a></p>
          </div>
          <a href="onboard.html" class="btn btn-primary" style="width:auto; padding:10px 20px; text-decoration:none; display:inline-flex; align-items:center; gap:8px;"><i class="ti ti-user-plus"></i> Add New Staff</a>
        </div>

        <div class="ms-list">
          <div class="ms-header-row"><div>Staff Member</div><div>Role</div><div>Department</div><div>Email</div><div>Status</div><div>Actions</div></div>
          <div id="msRows"><div class="ms-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script src="assets/presence.js"></script>
  <script>
    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role !== 'admin') {
          document.body.innerHTML = '<div style="padding:40px; font-family:sans-serif;">Admin access only.</div>';
          return;
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadStaff();
    }

    async function loadStaff() {
      const rows = document.getElementById('msRows');
      try {
        const result = await apiRequest('/admin/all-staff');
        if (result.staff.length === 0) {
          rows.innerHTML = '<div class="ms-empty">No staff yet.</div>';
          return;
        }
        rows.innerHTML = result.staff.map(s => {
          const statusHtml = s.isActive ? '<span class="ms-status active">Active</span>' : '<span class="ms-status inactive">Deactivated</span>';
          const actionBtn = s.isActive
            ? '<button class="ms-action-btn" onclick="deactivate(\'' + s.id + '\')">Deactivate</button>'
            : '<button class="ms-action-btn reactivate" onclick="reactivate(\'' + s.id + '\')">Reactivate</button>';
          return '<div class="ms-row">' +
            '<div>' + s.fullName + '</div>' +
            '<div>' + s.role + '</div>' +
            '<div>' + (s.department || '—') + '</div>' +
            '<div style="overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">' + s.email + '</div>' +
            '<div>' + statusHtml + '</div>' +
            '<div>' + actionBtn + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="ms-empty">Could not load staff.</div>';
      }
    }

    async function deactivate(id) {
      if (!confirm('Deactivate this staff member? They will no longer be able to log in.')) return;
      try {
        await apiRequest('/admin/staff/' + id, { method: 'DELETE' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function reactivate(id) {
      try {
        await apiRequest('/admin/staff/' + id + '/reactivate', { method: 'POST' });
        loadStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_MANAGE-STAFF_HTML

cat > accounting/directory.html << 'EOF_ACCOUNTING_DIRECTORY_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Staff Directory — MACDEN Portal</title>
  <link rel="stylesheet" href="assets/portal-style.css">
  <link rel="stylesheet" href="assets/portal-shell.css">
  <link rel="stylesheet" href="assets/portal-inbox.css">
  <style>
    .dir-toolbar { display: flex; gap: 12px; margin-bottom: 18px; }
    .dir-toolbar input {
      flex: 1; max-width: 380px; background: var(--surface); border: 1px solid var(--border);
      border-radius: var(--radius-sm); padding: 10px 14px; font-size: 13px; font-family: var(--font-body);
      color: var(--text-primary);
    }
    .dir-list { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius-md); overflow: hidden; }
    .dir-header-row { display: grid; grid-template-columns: 220px 160px 160px 1fr 130px; gap: 14px; padding: 12px 20px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-muted); border-bottom: 1px solid var(--border); }
    .dir-row { display: grid; grid-template-columns: 220px 160px 160px 1fr 130px; gap: 14px; align-items: center; padding: 13px 20px; border-bottom: 1px solid var(--border); cursor: pointer; }
    .dir-row:last-child { border-bottom: none; }
    .dir-row:hover { background: var(--surface-raised); }
    .dir-name-cell { display: flex; align-items: center; gap: 10px; font-size: 13.5px; font-weight: 600; color: var(--text-primary); }
    .dir-avatar { width: 32px; height: 32px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 11.5px; font-weight: 700; flex-shrink: 0; position: relative; }
    .dir-cell { font-size: 12.5px; color: var(--text-secondary); }
    .dir-role-badge { display: inline-block; padding: 2px 9px; border-radius: 999px; font-size: 10.5px; font-weight: 700; text-transform: uppercase; background: var(--primary-dim); color: var(--primary); }
    .dir-empty { padding: 60px 20px; text-align: center; color: var(--text-muted); font-size: 13px; }

    .profile-field-row { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border); font-size: 13px; }
    .profile-field-row:last-child { border-bottom: none; }
    .profile-field-label { color: var(--text-secondary); }
    .profile-field-value { color: var(--text-primary); font-weight: 500; }
    .profile-field-value.muted { color: var(--text-muted); font-style: italic; font-weight: 400; }
    .profile-avatar-large { width: 72px; height: 72px; border-radius: 50%; background: var(--gold-dim); color: #a17a00; display: flex; align-items: center; justify-content: center; font-size: 24px; font-weight: 700; margin: 0 auto 14px; }
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
        <a href="directory.html" class="sidebar-link active"><i class="ti ti-users"></i> Directory</a>
        <a href="leave.html" class="sidebar-link"><i class="ti ti-calendar-event"></i> Leave &amp; Requests</a>
        <a href="documents.html" class="sidebar-link"><i class="ti ti-file-text"></i> Documents</a>
        <a href="policies.html" class="sidebar-link"><i class="ti ti-book"></i> Policies</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
      <div class="sidebar-logout">
        <button id="logoutBtn"><i class="ti ti-logout"></i> Logout</button>
      </div>
    </div>

    <div class="main-content">
      <div class="topbar">
        <div class="topbar-search"><input type="text" placeholder="Search messages, people, documents…"></div>
        <button class="topbar-bell"><i class="ti ti-bell"></i></button>
        <img class="topbar-avatar" src="assets/logo.jpeg" alt="You">
      </div>

      <div class="page-body">
        <h1 class="page-greeting" style="font-size: 22px;">Staff Directory</h1>
        <p class="page-greeting-sub"><a href="dashboard.html" style="color: var(--primary); text-decoration:none; font-weight:600;">← Back to dashboard</a></p>

        <div class="dir-toolbar">
          <input type="text" id="dirSearch" placeholder="Search by name or username…">
          <a href="manage-staff.html" class="btn btn-primary" id="manageStaffLink" style="width:auto; padding:10px 18px; text-decoration:none; display:none; align-items:center; gap:8px; margin-left:auto;"><i class="ti ti-settings"></i> Manage Staff</a>
        </div>

        <div class="dir-list">
          <div class="dir-header-row">
            <div>Staff Member</div><div>Role</div><div>Department</div><div>Email</div><div>Status</div>
          </div>
          <div id="dirRows">
            <div class="dir-empty">Loading…</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="profileModalBackdrop">
    <div class="modal" style="width: 380px; text-align: center;">
      <button onclick="closeProfileModal()" style="float:right; background:none; border:none; cursor:pointer; color:var(--text-muted); font-size:16px;"><i class="ti ti-x"></i></button>
      <div class="profile-avatar-large" id="profileAvatar">—</div>
      <h3 id="profileName" style="text-align:center; font-size:17px;">—</h3>
      <p id="profileRole" style="text-align:center; color:var(--text-secondary); font-size:12.5px; margin-top:-6px;">—</p>

      <div style="text-align:left; margin-top:18px;">
        <div class="profile-field-row"><span class="profile-field-label">Department</span><span class="profile-field-value" id="profileDept">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Username</span><span class="profile-field-value" id="profileUsername">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Email</span><span class="profile-field-value" id="profileEmail">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Date Joined</span><span class="profile-field-value" id="profileDate">—</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Phone</span><span class="profile-field-value muted">Not yet added</span></div>
        <div class="profile-field-row"><span class="profile-field-label">Branch</span><span class="profile-field-value muted">Not yet added</span></div>
      </div>

      <button class="btn btn-primary" id="messageProfileBtn" style="margin-top:18px; display:inline-flex; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px;">
        <i class="ti ti-mail"></i> Message
      </button>
    </div>
  </div>

  <script src="assets/api.js"></script>
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

    let staffCache = [];
    let searchTimeout = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        if (result.staff.role === 'admin') {
          document.getElementById('manageStaffLink').style.display = 'inline-flex';
        }
      } catch (err) {
        window.location.href = 'login.html';
        return;
      }
      loadUnreadBadge();
      loadDirectory('');
    }

    async function loadDirectory(query) {
      const rows = document.getElementById('dirRows');
      try {
        const result = await apiRequest('/staff?search=' + encodeURIComponent(query));
        staffCache = result.staff;

        if (result.staff.length === 0) {
          rows.innerHTML = '<div class="dir-empty">No staff found.</div>';
          return;
        }

        rows.innerHTML = result.staff.map(s => {
          const statusDot = s.isOnline ? '<span style="color:var(--primary-light); font-size:11px;">● Online</span>' : '<span style="color:var(--text-muted); font-size:11px;">○ Offline</span>';
          return '<div class="dir-row" onclick="openProfile(\'' + s.id + '\')">' +
            '<div class="dir-name-cell"><span class="dir-avatar">' + initials(s.full_name) + '</span>' + s.full_name + '</div>' +
            '<div class="dir-cell"><span class="dir-role-badge">' + s.role + '</span></div>' +
            '<div class="dir-cell">' + (s.department || '—') + '</div>' +
            '<div class="dir-cell">' + s.email + '</div>' +
            '<div class="dir-cell">' + statusDot + '</div>' +
            '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="dir-empty">Could not load directory.</div>';
      }
    }

    document.getElementById('dirSearch').addEventListener('input', (e) => {
      clearTimeout(searchTimeout);
      searchTimeout = setTimeout(() => loadDirectory(e.target.value.trim()), 250);
    });

    function openProfile(id) {
      const person = staffCache.find(s => s.id === id);
      if (!person) return;

      document.getElementById('profileAvatar').textContent = initials(person.full_name);
      document.getElementById('profileName').textContent = person.full_name;
      document.getElementById('profileRole').textContent = person.role + (person.department ? ' · ' + person.department : '');
      document.getElementById('profileDept').textContent = person.department || '—';
      document.getElementById('profileUsername').textContent = person.username;
      document.getElementById('profileEmail').textContent = person.email;
      document.getElementById('profileDate').textContent = person.dateStarted ? new Date(person.dateStarted).toLocaleDateString() : '—';

      document.getElementById('messageProfileBtn').onclick = () => {
        window.location.href = 'compose.html?to=' + person.id + '&name=' + encodeURIComponent(person.full_name);
      };

      document.getElementById('profileModalBackdrop').classList.add('visible');
    }

    function closeProfileModal() {
      document.getElementById('profileModalBackdrop').classList.remove('visible');
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_DIRECTORY_HTML

echo "Onboarding wizard and Manage Staff added."