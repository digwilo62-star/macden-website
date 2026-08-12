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
