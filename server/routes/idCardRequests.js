// server/routes/idCardRequests.js
//
// Staff ID card request + approval flow, same shape as your existing
// leave-request system: staff submits a request, it sits pending until
// an admin approves or rejects it. Approval doesn't generate a static
// file -- it just flips a status flag. The actual card is rendered live
// (with a live QR code) whenever someone with permission opens the view
// page, using portal/id-card-view.html.
//
// *** FLAGGED ASSUMPTION -- PLEASE VERIFY ***
// This file assumes:
//   - req.session.staffId holds the logged-in user's staff.id (UUID)
//   - req.session.role holds their role, and the admin role string is 'admin'
// If your actual session shape is different (e.g. req.session.user.id,
// or req.user from a different auth strategy), update getSessionStaffId()
// and isAdmin() below -- those two functions are the only places this
// assumption is used.

const express = require('express');
const router = express.Router();
const QRCode = require('qrcode');
const requireAuth = require('../middleware/requireAuth');
const { supabase } = require('../config/supabaseClient');

router.use(requireAuth);

// --- adjust these two if the session shape is different ---
function getSessionStaffId(req) {
  return req.session && req.session.staffId;
}
function isAdmin(req) {
  return !!(req.session && req.session.role === 'admin');
}
// ------------------------------------------------------------

// Staff: submit a new request
router.post('/api/id-card/request', async (req, res) => {
  const staffId = getSessionStaffId(req);
  if (!staffId) return res.status(401).json({ error: 'Not authenticated.' });

  try {
    const { data: existing, error: existingErr } = await supabase
      .from('id_card_requests')
      .select('id, status')
      .eq('staff_ref_id', staffId)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingErr) throw existingErr;

    if (existing && existing.status === 'pending') {
      return res.status(409).json({ error: 'You already have a pending request.' });
    }
    if (existing && existing.status === 'approved') {
      return res.status(409).json({ error: 'You already have an approved card.', requestId: existing.id });
    }

    const { data: created, error: insertErr } = await supabase
      .from('id_card_requests')
      .insert({ staff_ref_id: staffId })
      .select('id, status, requested_at')
      .single();

    if (insertErr) throw insertErr;

    return res.json({ success: true, request: created });
  } catch (err) {
    console.error('[ID-CARD-REQUEST-ERROR]', err);
    return res.status(500).json({ error: 'Could not submit request.' });
  }
});

// Staff: check their own latest request status
router.get('/api/id-card/request/status', async (req, res) => {
  const staffId = getSessionStaffId(req);
  if (!staffId) return res.status(401).json({ error: 'Not authenticated.' });

  try {
    const { data, error } = await supabase
      .from('id_card_requests')
      .select('id, status, requested_at, reviewed_at, rejection_reason')
      .eq('staff_ref_id', staffId)
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) throw error;
    return res.json({ request: data || null });
  } catch (err) {
    console.error('[ID-CARD-STATUS-ERROR]', err);
    return res.status(500).json({ error: 'Could not check request status.' });
  }
});

// Admin: list pending requests
router.get('/api/id-card/requests', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const { data, error } = await supabase
      .from('id_card_requests')
      .select('id, status, requested_at, staff:staff_ref_id (id, full_name, staff_id, role, department_id, departments(name), photo_url)')
      .eq('status', 'pending')
      .order('requested_at', { ascending: true });

    if (error) throw error;
    return res.json({ requests: data });
  } catch (err) {
    console.error('[ID-CARD-LIST-ERROR]', err);
    return res.status(500).json({ error: 'Could not load requests.' });
  }
});

// Admin: approve a request
router.post('/api/id-card/requests/:id/approve', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const reviewerId = getSessionStaffId(req);

  try {
    const { data: reqRow, error: reqErr } = await supabase
      .from('id_card_requests')
      .select('id, staff_ref_id, staff:staff_ref_id (staff_id)')
      .eq('id', req.params.id)
      .single();

    if (reqErr || !reqRow) return res.status(404).json({ error: 'Request not found.' });

    if (!reqRow.staff || !reqRow.staff.staff_id) {
      return res.status(400).json({
        error: 'This staff member has no staff_id assigned yet. Assign one via Edit Staff before approving.'
      });
    }

    const { error: updateErr } = await supabase
      .from('id_card_requests')
      .update({ status: 'approved', reviewed_at: new Date().toISOString(), reviewed_by: reviewerId })
      .eq('id', req.params.id);

    if (updateErr) throw updateErr;
    return res.json({ success: true });
  } catch (err) {
    console.error('[ID-CARD-APPROVE-ERROR]', err);
    return res.status(500).json({ error: 'Could not approve request.' });
  }
});

// Admin: reject a request
router.post('/api/id-card/requests/:id/reject', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });
  const reviewerId = getSessionStaffId(req);
  const reason = (req.body && req.body.reason) || null;

  try {
    const { error } = await supabase
      .from('id_card_requests')
      .update({ status: 'rejected', reviewed_at: new Date().toISOString(), reviewed_by: reviewerId, rejection_reason: reason })
      .eq('id', req.params.id);

    if (error) throw error;
    return res.json({ success: true });
  } catch (err) {
    console.error('[ID-CARD-REJECT-ERROR]', err);
    return res.status(500).json({ error: 'Could not reject request.' });
  }
});

// Staff or admin: fetch the real data + a live QR code for an APPROVED request.
// This is what portal/id-card-view.html calls to render the actual card.
router.get('/api/id-card/card/:requestId', async (req, res) => {
  const staffId = getSessionStaffId(req);
  if (!staffId) return res.status(401).json({ error: 'Not authenticated.' });

  try {
    const { data: reqRow, error: reqErr } = await supabase
      .from('id_card_requests')
      .select('id, status, staff_ref_id, staff:staff_ref_id (id, full_name, staff_id, role, branch, photo_url, department_id, departments(name), verification_token)')
      .eq('id', req.params.requestId)
      .single();

    if (reqErr || !reqRow) return res.status(404).json({ error: 'Request not found.' });
    if (reqRow.status !== 'approved') return res.status(403).json({ error: 'This request has not been approved yet.' });

    const isOwner = reqRow.staff_ref_id === staffId;
    if (!isOwner && !isAdmin(req)) {
      return res.status(403).json({ error: 'Not authorized to view this card.' });
    }

    const staff = reqRow.staff;
    const verifyUrl = `https://macden.com.ng/portal/verify.html?token=${staff.verification_token}`;
    const qrDataUrl = await QRCode.toDataURL(verifyUrl, {
      errorCorrectionLevel: 'H',
      color: { dark: '#0d5c2f', light: '#fbfaf6' }
    });

    return res.json({
      full_name: staff.full_name,
      staff_id: staff.staff_id,
      department: staff.departments ? staff.departments.name : null,
      role: staff.role,
      branch: staff.branch || null,
      photo_url: staff.photo_url || null,
      qr_data_url: qrDataUrl
    });
  } catch (err) {
    console.error('[ID-CARD-VIEW-ERROR]', err);
    return res.status(500).json({ error: 'Could not load card data.' });
  }
});

module.exports = router;
