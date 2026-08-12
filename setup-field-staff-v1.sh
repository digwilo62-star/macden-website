#!/bin/bash
# setup-field-staff-v1.sh
#
# Adds the Field Staff system: people who need a physical MACDEN ID badge
# but never log into the portal (drivers, loaders, etc -- no account, no
# email, no password). Creates:
#   - server/routes/fieldStaff.js -- CRUD + card generation, admin-only
#   - portal/field-staff.html     -- the admin management page
#   - server/migrations/add_field_staff.sql (reference, NOT auto-run)
#   - wires the route into server/server.js
#
# Safe to re-run.

set -e

echo "==> Creating server/routes/fieldStaff.js"
mkdir -p server/routes
cat > server/routes/fieldStaff.js << 'ROUTE_EOF'
// server/routes/fieldStaff.js
//
// Manages "field staff" -- people who need a physical MACDEN ID badge but
// never log into the portal (no email, no password, no account at all).
// Entirely admin-managed: an admin adds them, generates their card, and
// can deactivate them later (which invalidates their QR verification too,
// same as it does for real staff accounts).

const express = require('express');
const router = express.Router();
const QRCode = require('qrcode');
const requireAuth = require('../middleware/requireAuth');
const supabase = require('../config/supabaseClient');

router.use(requireAuth);

function isAdmin(req) {
  return !!(req.session && req.session.staff && req.session.staff.role === 'admin');
}

async function generateUniqueStaffId(fieldStaffId) {
  const year = new Date().getFullYear();
  const MAX_ATTEMPTS = 8;

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const rand = Math.floor(1000 + Math.random() * 9000);
    const candidate = `MAC-${year}-${rand}`;

    const { error } = await supabase
      .from('field_staff')
      .update({ staff_id: candidate })
      .eq('id', fieldStaffId);

    if (!error) return candidate;
    if (error.code !== '23505') throw error;
  }

  throw new Error('Could not generate a unique Staff ID after several attempts.');
}

// List all field staff
router.get('/api/field-staff', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const { data, error } = await supabase
      .from('field_staff')
      .select('id, full_name, role, department_id, departments(name), phone, branch, photo_url, staff_id, is_active, created_at')
      .order('created_at', { ascending: false });

    if (error) throw error;
    return res.json({ fieldStaff: data });
  } catch (err) {
    console.error('[FIELD-STAFF-LIST-ERROR]', err);
    return res.status(500).json({ error: 'Could not load field staff.' });
  }
});

// Add a new field staff member
router.post('/api/field-staff', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const { fullName, role, departmentId, phone, branch } = req.body;

  if (!fullName || !fullName.trim()) {
    return res.status(400).json({ error: 'Full name is required.' });
  }

  try {
    const { data, error } = await supabase
      .from('field_staff')
      .insert({
        full_name: fullName.trim(),
        role: role || null,
        department_id: departmentId || null,
        phone: phone || null,
        branch: branch || null,
        created_by: req.session.staff.id
      })
      .select('id')
      .single();

    if (error) throw error;
    return res.json({ success: true, id: data.id });
  } catch (err) {
    console.error('[FIELD-STAFF-CREATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not add field staff member.' });
  }
});

// Edit an existing field staff member
router.put('/api/field-staff/:id', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const { fullName, role, departmentId, phone, branch } = req.body;

  try {
    const { error } = await supabase
      .from('field_staff')
      .update({
        full_name: fullName ? fullName.trim() : undefined,
        role: role || null,
        department_id: departmentId || null,
        phone: phone || null,
        branch: branch || null
      })
      .eq('id', req.params.id);

    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-EDIT-ERROR]', err);
    return res.status(500).json({ error: 'Could not update field staff member.' });
  }
});

// Deactivate / reactivate
router.post('/api/field-staff/:id/deactivate', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  try {
    const { error } = await supabase.from('field_staff').update({ is_active: false }).eq('id', req.params.id);
    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-DEACTIVATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not deactivate.' });
  }
});

router.post('/api/field-staff/:id/reactivate', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  try {
    const { error } = await supabase.from('field_staff').update({ is_active: true }).eq('id', req.params.id);
    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[FIELD-STAFF-REACTIVATE-ERROR]', err);
    return res.status(500).json({ error: 'Could not reactivate.' });
  }
});

// Generate/assign a staff_id if missing -- no request/approval concept
// here, the admin adding them IS the approval.
router.post('/api/field-staff/:id/generate-id', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const { data: person, error: fetchErr } = await supabase
      .from('field_staff')
      .select('id, staff_id')
      .eq('id', req.params.id)
      .single();

    if (fetchErr || !person) return res.status(404).json({ error: 'Field staff member not found.' });

    let staffId = person.staff_id;
    if (!staffId) {
      staffId = await generateUniqueStaffId(req.params.id);
    }

    return res.json({ success: true, staffId, fieldStaffId: req.params.id });
  } catch (err) {
    console.error('[FIELD-STAFF-GENERATE-ID-ERROR]', err);
    return res.status(500).json({ error: 'Could not generate ID card.' });
  }
});

// Card data + live QR for a field staff member's card view page
router.get('/api/field-staff/:id/card', async (req, res) => {
  try {
    const { data: person, error } = await supabase
      .from('field_staff')
      .select('full_name, staff_id, role, branch, photo_url, department_id, departments(name), verification_token, is_active')
      .eq('id', req.params.id)
      .single();

    if (error || !person) return res.status(404).json({ error: 'Field staff member not found.' });
    if (!person.staff_id) return res.status(400).json({ error: 'No Staff ID assigned yet.' });

    const verifyUrl = `https://macden.com.ng/portal/verify.html?token=${person.verification_token}`;
    const qrDataUrl = await QRCode.toDataURL(verifyUrl, {
      errorCorrectionLevel: 'H',
      color: { dark: '#0d5c2f', light: '#fbfaf6' }
    });

    return res.json({
      full_name: person.full_name,
      staff_id: person.staff_id,
      department: person.departments ? person.departments.name : null,
      role: person.role,
      branch: person.branch || null,
      photo_url: person.photo_url || null,
      qr_data_url: qrDataUrl
    });
  } catch (err) {
    console.error('[FIELD-STAFF-CARD-ERROR]', err);
    return res.status(500).json({ error: 'Could not load card data.' });
  }
});

module.exports = router;
ROUTE_EOF

echo "==> Creating portal/field-staff.html"
mkdir -p portal
cat > portal/field-staff.html << 'PAGE_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Field Staff — MACDEN Portal</title>
<link rel="stylesheet" href="assets/portal-style.css">
<link rel="stylesheet" href="assets/portal-shell.css">
<style>
  .fs-toolbar{ display:flex; justify-content:space-between; align-items:center; margin-bottom:18px; }
  .fs-list{ background:var(--surface); border:1px solid var(--border); border-radius:var(--radius-md); overflow-x:auto; }
  .fs-header-row{ display:grid; min-width:700px; grid-template-columns: minmax(140px,1fr) minmax(100px,140px) minmax(100px,140px) minmax(110px,140px) minmax(70px,90px) minmax(180px,220px); gap:12px; padding:12px 18px; font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); border-bottom:1px solid var(--border); }
  .fs-row{ display:grid; min-width:700px; grid-template-columns: minmax(140px,1fr) minmax(100px,140px) minmax(100px,140px) minmax(110px,140px) minmax(70px,90px) minmax(180px,220px); gap:12px; align-items:center; padding:12px 18px; border-bottom:1px solid var(--border); font-size:12.5px; }
  .fs-row:last-child{ border-bottom:none; }
  .fs-empty{ padding:50px 18px; text-align:center; color:var(--text-muted); font-size:13px; }
  .fs-status{ display:inline-block; padding:2px 9px; border-radius:999px; font-size:10.5px; font-weight:700; }
  .fs-status.active{ background:var(--success-dim); color:var(--success); }
  .fs-status.inactive{ background:var(--error-dim); color:var(--error); }
  .fs-action-btn{ border:1px solid var(--border); background:var(--surface); border-radius:var(--radius-sm); padding:5px 11px; font-size:11px; font-weight:600; cursor:pointer; font-family:var(--font-body); color:var(--text-primary); margin-right:4px; margin-bottom:4px; }
  .fs-action-btn:hover{ border-color:var(--primary); color:var(--primary); }
  .fs-action-btn.danger:hover{ border-color:var(--error); color:var(--error); background:var(--error-dim); }
  .fs-action-btn.reactivate{ background:var(--success-dim); color:var(--success); border-color:transparent; }

  .modal-backdrop{ display:none; position:fixed; inset:0; background:rgba(0,0,0,0.4); align-items:center; justify-content:center; z-index:100; }
  .modal-backdrop.visible{ display:flex; }
  .modal{ background:var(--surface); border-radius:var(--radius-md); padding:24px; width:380px; max-width:90vw; }
  .modal h3{ margin-bottom:16px; }
  .modal-actions{ display:flex; justify-content:flex-end; gap:10px; margin-top:8px; }
  .field-label{ display:block; font-size:12.5px; font-weight:600; margin-bottom:6px; }
  .field-input{ width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box; margin-bottom:12px; }
</style>
</head>
<body>
  <div class="app-shell">
    <div class="sidebar">
      <div class="sidebar-brand"><img src="assets/logo.jpeg" alt="MACDEN"><span>MACDEN</span></div>
      <nav class="sidebar-nav">
        <a href="dashboard.html" class="sidebar-link"><i class="ti ti-layout-dashboard"></i> Dashboard</a>
        <a href="directory.html" class="sidebar-link"><i class="ti ti-users"></i> Directory</a>
        <a href="settings.html" class="sidebar-link"><i class="ti ti-settings"></i> Settings</a>
      </nav>
    </div>

    <div class="main-content">
      <div class="page-body">
        <div class="fs-toolbar">
          <div>
            <h1 class="page-greeting" style="font-size:22px;">Field Staff</h1>
            <p class="page-greeting-sub" style="margin:0;">
              <a href="manage-staff.html" style="color:var(--primary); text-decoration:none; font-weight:600;">&larr; Back to Manage Staff</a>
            </p>
            <p style="font-size:12.5px; color:var(--text-muted); margin-top:6px; max-width:520px;">
              People who need a physical MACDEN ID badge but never log into the portal —
              drivers, loaders, and other field workers. No account, no email, no password.
            </p>
          </div>
          <button class="btn btn-primary" id="addFieldStaffBtn" style="width:auto; padding:10px 20px; display:inline-flex; align-items:center; gap:8px;">
            <i class="ti ti-user-plus"></i> Add Field Worker
          </button>
        </div>

        <div class="fs-list">
          <div class="fs-header-row"><div>Name</div><div>Role</div><div>Department</div><div>Staff ID</div><div>Status</div><div>Actions</div></div>
          <div id="fsRows"><div class="fs-empty">Loading…</div></div>
        </div>
      </div>
    </div>
  </div>

  <div class="modal-backdrop" id="fieldStaffModalBackdrop">
    <div class="modal">
      <h3 id="fieldStaffModalTitle">Add Field Worker</h3>
      <div id="fieldStaffAlert" class="alert alert-error"></div>

      <label class="field-label">Full Name</label>
      <input type="text" id="fsFullName" class="field-input">

      <label class="field-label">Role</label>
      <input type="text" id="fsRole" class="field-input" placeholder="e.g. Delivery Driver">

      <label class="field-label">Department</label>
      <select id="fsDepartmentId" class="field-input">
        <option value="">None</option>
      </select>

      <label class="field-label">Phone</label>
      <input type="text" id="fsPhone" class="field-input">

      <label class="field-label">Branch</label>
      <input type="text" id="fsBranch" class="field-input">

      <div class="modal-actions">
        <button class="btn btn-ghost" id="fieldStaffCancelBtn">Cancel</button>
        <button class="btn btn-primary" id="fieldStaffSaveBtn">Save</button>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    let editingId = null;

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
      loadDepartments();
      loadFieldStaff();
    }

    async function loadDepartments() {
      try {
        const result = await apiRequest('/admin/departments');
        document.getElementById('fsDepartmentId').innerHTML =
          '<option value="">None</option>' +
          result.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');
      } catch (err) { /* non-fatal */ }
    }

    async function loadFieldStaff() {
      const rows = document.getElementById('fsRows');
      try {
        const res = await fetch('/api/field-staff', { credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not load field staff.');

        if (!data.fieldStaff.length) {
          rows.innerHTML = '<div class="fs-empty">No field staff added yet.</div>';
          return;
        }

        rows.innerHTML = data.fieldStaff.map(p => {
          const statusHtml = p.is_active
            ? '<span class="fs-status active">Active</span>'
            : '<span class="fs-status inactive">Deactivated</span>';
          const deptName = p.departments ? p.departments.name : '—';
          const staffIdText = p.staff_id || '<span style="color:var(--text-muted);">Not assigned</span>';

          const toggleBtn = p.is_active
            ? '<button class="fs-action-btn danger" onclick="deactivateFS(\'' + p.id + '\')">Deactivate</button>'
            : '<button class="fs-action-btn reactivate" onclick="reactivateFS(\'' + p.id + '\')">Reactivate</button>';

          return '<div class="fs-row">' +
            '<div>' + p.full_name + '</div>' +
            '<div>' + (p.role || '—') + '</div>' +
            '<div>' + deptName + '</div>' +
            '<div>' + staffIdText + '</div>' +
            '<div>' + statusHtml + '</div>' +
            '<div>' +
              '<button class="fs-action-btn" onclick="editFS(\'' + p.id + '\')">Edit</button>' +
              '<button class="fs-action-btn" onclick="generateCard(\'' + p.id + '\')">ID Card</button>' +
              toggleBtn +
            '</div>' +
          '</div>';
        }).join('');
      } catch (err) {
        rows.innerHTML = '<div class="fs-empty">' + err.message + '</div>';
      }
    }

    function openAddModal() {
      editingId = null;
      document.getElementById('fieldStaffModalTitle').textContent = 'Add Field Worker';
      document.getElementById('fsFullName').value = '';
      document.getElementById('fsRole').value = '';
      document.getElementById('fsDepartmentId').value = '';
      document.getElementById('fsPhone').value = '';
      document.getElementById('fsBranch').value = '';
      document.getElementById('fieldStaffModalBackdrop').classList.add('visible');
    }

    async function editFS(id) {
      try {
        const res = await fetch('/api/field-staff', { credentials: 'include' });
        const data = await res.json();
        const p = data.fieldStaff.find(x => x.id === id);
        if (!p) return;

        editingId = id;
        document.getElementById('fieldStaffModalTitle').textContent = 'Edit Field Worker';
        document.getElementById('fsFullName').value = p.full_name || '';
        document.getElementById('fsRole').value = p.role || '';
        document.getElementById('fsDepartmentId').value = p.department_id || '';
        document.getElementById('fsPhone').value = p.phone || '';
        document.getElementById('fsBranch').value = p.branch || '';
        document.getElementById('fieldStaffModalBackdrop').classList.add('visible');
      } catch (err) {
        alert('Could not load this person\'s details.');
      }
    }

    document.getElementById('addFieldStaffBtn').addEventListener('click', openAddModal);
    document.getElementById('fieldStaffCancelBtn').addEventListener('click', () => {
      document.getElementById('fieldStaffModalBackdrop').classList.remove('visible');
    });

    document.getElementById('fieldStaffSaveBtn').addEventListener('click', async () => {
      const alertEl = document.getElementById('fieldStaffAlert');
      alertEl.style.display = 'none';

      const body = {
        fullName: document.getElementById('fsFullName').value.trim(),
        role: document.getElementById('fsRole').value.trim(),
        departmentId: document.getElementById('fsDepartmentId').value || null,
        phone: document.getElementById('fsPhone').value.trim(),
        branch: document.getElementById('fsBranch').value.trim()
      };

      if (!body.fullName) {
        alertEl.textContent = 'Full name is required.';
        alertEl.style.display = 'block';
        return;
      }

      const url = editingId ? '/api/field-staff/' + editingId : '/api/field-staff';
      const method = editingId ? 'PUT' : 'POST';

      try {
        const res = await fetch(url, {
          method,
          credentials: 'include',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not save.');

        document.getElementById('fieldStaffModalBackdrop').classList.remove('visible');
        loadFieldStaff();
      } catch (err) {
        alertEl.textContent = err.message;
        alertEl.style.display = 'block';
      }
    });

    async function deactivateFS(id) {
      if (!confirm('Deactivate this field worker? Their ID card will stop verifying as active.')) return;
      try {
        const res = await fetch('/api/field-staff/' + id + '/deactivate', { method: 'POST', credentials: 'include' });
        if (!res.ok) throw new Error('Could not deactivate.');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function reactivateFS(id) {
      try {
        const res = await fetch('/api/field-staff/' + id + '/reactivate', { method: 'POST', credentials: 'include' });
        if (!res.ok) throw new Error('Could not reactivate.');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    async function generateCard(id) {
      try {
        const res = await fetch('/api/field-staff/' + id + '/generate-id', { method: 'POST', credentials: 'include' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not generate ID card.');
        window.open('id-card-view.html?fieldId=' + id, '_blank');
        loadFieldStaff();
      } catch (err) {
        alert(err.message);
      }
    }

    init();
  </script>
</body>
</html>
PAGE_EOF

echo "==> Saving the SQL migration to server/migrations/ for reference (NOT auto-run)"
mkdir -p server/migrations
cat > server/migrations/add_field_staff.sql << 'SQL_EOF'
-- Run in the Supabase SQL editor (macden-accounting project).
-- Separate from `staff` entirely -- these are people who need a physical
-- ID badge but never log into the portal. No email, no password, no
-- account. Admin-managed only.

CREATE TABLE IF NOT EXISTS field_staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  role TEXT,
  department_id UUID REFERENCES departments(id),
  phone TEXT,
  branch TEXT,
  photo_url TEXT,
  staff_id TEXT UNIQUE,
  verification_token UUID NOT NULL DEFAULT gen_random_uuid(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES staff(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_field_staff_verification_token ON field_staff(verification_token);
CREATE INDEX IF NOT EXISTS idx_field_staff_active ON field_staff(is_active);
SQL_EOF

echo "==> Wiring the route into server/server.js"
if grep -q "require('./routes/fieldStaff')" server/server.js; then
  echo "    Already wired in -- skipping (safe to re-run)."
else
  if ! grep -qF "app.use('/api/accounting', requireAuth);" server/server.js; then
    echo "    ERROR: could not find the expected anchor line in server/server.js."
    echo "    Nothing was changed."
    exit 1
  fi

  cat > .tmp-patch-fieldstaff.js << 'NODE_EOF'
const fs = require('fs');
const filePath = 'server/server.js';
let content = fs.readFileSync(filePath, 'utf8');

const anchor = "app.use('/api/accounting', requireAuth);";
const insertion =
  "// --- MACDEN Field Staff (auth required, checked inside the route file) ---\n" +
  "const fieldStaffRoutes = require('./routes/fieldStaff');\n" +
  "app.use(fieldStaffRoutes);\n" +
  "// --- end field staff block ---\n\n";

content = content.replace(anchor, insertion + anchor);
fs.writeFileSync(filePath, content);
console.log('    Inserted require + mount before the requireAuth line.');
NODE_EOF

  node .tmp-patch-fieldstaff.js
  rm .tmp-patch-fieldstaff.js
fi

echo ""
echo "=================================================================="
echo "Files created and route wired. Remaining manual steps:"
echo ""
echo "1. Run server/migrations/add_field_staff.sql in the Supabase SQL"
echo "   editor (macden-accounting project)."
echo ""
echo "2. Also run fix-verify-fieldstaff-v1.sh and"
echo "   fix-idcardview-fieldstaff-v1.sh (separate scripts) so QR scans"
echo "   and the card viewer recognize field staff too."
echo ""
echo "3. Also run fix-managestaff-fieldlink-v1.sh to remove the old"
echo "   ID Card button from the regular staff table and add the"
echo "   Field Staff link instead."
echo ""
echo "Then push with your usual save-progress.sh."
echo "=================================================================="
