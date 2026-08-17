// server/routes/attendance.js
//
// QR-scan based attendance: first scan of the day = check-in, second
// scan = check-out. Works for both regular staff and Field Staff, using
// the same verification_token already printed on every ID card's QR code.
//
// The kiosk device stays logged in (any valid session works -- set up
// one dedicated account for the reception/entrance device, or keep an
// admin logged in there). This endpoint deliberately does NOT require
// admin specifically, since a kiosk terminal isn't a personal admin session.

const express = require('express');
const router = express.Router();
const requireAuth = require('../middleware/requireAuth');
const supabase = require('../config/supabaseClient');

router.use(requireAuth);

function isAdmin(req) {
  return !!(req.session && req.session.staff && req.session.staff.role === 'admin');
}

function todayDateString() {
  // Server-side date, not client-supplied -- avoids clock-skew/spoofing issues
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

// Uploads a base64 photo (from the kiosk's camera) to Supabase Storage.
// Non-fatal on failure -- a photo upload problem should never block the
// actual attendance record from being saved, since the scan itself
// matters more than the photo.
async function uploadAttendancePhoto(photoDataUrl, filenamePrefix) {
  if (!photoDataUrl || !photoDataUrl.startsWith('data:image/')) return null;
  try {
    const matches = photoDataUrl.match(/^data:image\/(\w+);base64,(.+)$/);
    if (!matches) return null;
    const ext = matches[1] === 'jpeg' ? 'jpg' : matches[1];
    const buffer = Buffer.from(matches[2], 'base64');
    const fileName = `${filenamePrefix}-${Date.now()}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from('attendance-photos')
      .upload(fileName, buffer, { contentType: `image/${matches[1]}`, upsert: true });

    if (uploadError) {
      console.error('[ATTENDANCE-PHOTO-UPLOAD-ERROR]', uploadError);
      return null;
    }

    const { data: publicUrlData } = supabase.storage.from('attendance-photos').getPublicUrl(fileName);
    return publicUrlData.publicUrl;
  } catch (err) {
    console.error('[ATTENDANCE-PHOTO-UPLOAD-UNEXPECTED-ERROR]', err);
    return null;
  }
}

// POST /api/attendance/scan -- called by the kiosk on every card scan
router.post('/api/attendance/scan', async (req, res) => {
  const { token, photo } = req.body;
  if (!token) return res.status(400).json({ error: 'No token provided.' });

  try {
    // Same staff-then-field_staff fallback lookup as verify.js
    const { data: staffMember } = await supabase
      .from('staff')
      .select('id, full_name, is_active, photo_url')
      .eq('verification_token', token)
      .maybeSingle();

    let person = staffMember;
    let personType = 'staff';

    if (!person) {
      const { data: fieldMember } = await supabase
        .from('field_staff')
        .select('id, full_name, is_active, photo_url')
        .eq('verification_token', token)
        .maybeSingle();
      person = fieldMember;
      personType = 'field_staff';
    }

    if (!person) {
      return res.status(404).json({ error: 'Card not recognized.' });
    }
    if (!person.is_active) {
      return res.status(403).json({ error: 'This card is not currently active.', full_name: person.full_name });
    }

    const refColumn = personType === 'staff' ? 'staff_ref_id' : 'field_staff_ref_id';
    const today = todayDateString();

    const { data: existing, error: fetchErr } = await supabase
      .from('attendance_logs')
      .select('id, check_in_time, check_out_time')
      .eq(refColumn, person.id)
      .eq('log_date', today)
      .maybeSingle();

    if (fetchErr) throw fetchErr;

    const now = new Date().toISOString();

    if (!existing) {
      // First scan today -- check in
      const photoUrl = await uploadAttendancePhoto(photo, `${person.id}-${today}-checkin`);

      const { error: insertErr } = await supabase
        .from('attendance_logs')
        .insert({ [refColumn]: person.id, log_date: today, check_in_time: now, check_in_photo_url: photoUrl });
      if (insertErr) throw insertErr;

      return res.json({
        action: 'check-in',
        full_name: person.full_name,
        photo_url: person.photo_url || null,
        time: now
      });
    }

    if (existing.check_in_time && !existing.check_out_time) {
      // Second scan today -- check out
      const photoUrl = await uploadAttendancePhoto(photo, `${person.id}-${today}-checkout`);

      const { error: updateErr } = await supabase
        .from('attendance_logs')
        .update({ check_out_time: now, check_out_photo_url: photoUrl })
        .eq('id', existing.id);
      if (updateErr) throw updateErr;

      return res.json({
        action: 'check-out',
        full_name: person.full_name,
        photo_url: person.photo_url || null,
        time: now
      });
    }

    // Already checked in AND out today -- don't overwrite, just report it
    return res.json({
      action: 'already-complete',
      full_name: person.full_name,
      photo_url: person.photo_url || null,
      check_in_time: existing.check_in_time,
      check_out_time: existing.check_out_time
    });

  } catch (err) {
    console.error('[ATTENDANCE-SCAN-ERROR]', err);
    return res.status(500).json({ error: 'Something went wrong recording attendance.' });
  }
});

// GET /api/attendance/logs?date=YYYY-MM-DD -- admin report view
router.get('/api/attendance/logs', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  const date = req.query.date || todayDateString();

  try {
    const { data, error } = await supabase
      .from('attendance_logs')
      .select(`
        id, log_date, check_in_time, check_out_time, check_in_photo_url, check_out_photo_url,
        staff:staff_ref_id (full_name, staff_id, departments(name)),
        field_staff:field_staff_ref_id (full_name, staff_id, departments(name))
      `)
      .eq('log_date', date)
      .order('check_in_time', { ascending: true });

    if (error) throw error;

    const logs = data.map(row => {
      const person = row.staff || row.field_staff;
      return {
        id: row.id,
        full_name: person ? person.full_name : 'Unknown',
        staff_id: person ? person.staff_id : null,
        department: person && person.departments ? person.departments.name : null,
        source: row.staff ? 'Staff' : 'Field Staff',
        check_in_time: row.check_in_time,
        check_out_time: row.check_out_time,
        check_in_photo_url: row.check_in_photo_url,
        check_out_photo_url: row.check_out_photo_url
      };
    });

    return res.json({ date, logs });
  } catch (err) {
    console.error('[ATTENDANCE-LOGS-ERROR]', err);
    return res.status(500).json({ error: 'Could not load attendance logs.' });
  }
});

// GET /api/attendance/my-today -- for the STAFF dashboard card. Only
// meaningful for regular staff (field staff have no login/session at all).
router.get('/api/attendance/my-today', async (req, res) => {
  try {
    const today = todayDateString();
    const { data, error } = await supabase
      .from('attendance_logs')
      .select('check_in_time, check_out_time')
      .eq('staff_ref_id', req.session.staff.id)
      .eq('log_date', today)
      .maybeSingle();

    if (error) throw error;

    return res.json({
      checkedIn: !!(data && data.check_in_time),
      checkInTime: data ? data.check_in_time : null,
      checkOutTime: data ? data.check_out_time : null
    });
  } catch (err) {
    console.error('[ATTENDANCE-MY-TODAY-ERROR]', err);
    return res.status(500).json({ error: 'Could not load your attendance status.' });
  }
});

// GET /api/attendance/summary-today -- for the ADMIN dashboard card.
router.get('/api/attendance/summary-today', async (req, res) => {
  if (!isAdmin(req)) return res.status(403).json({ error: 'Admin access required.' });

  try {
    const today = todayDateString();

    const [{ count: totalActive }, { data: checkedInRows }] = await Promise.all([
      supabase.from('staff').select('*', { count: 'exact', head: true }).eq('is_active', true),
      supabase.from('attendance_logs').select('id').eq('log_date', today).not('check_in_time', 'is', null)
    ]);

    return res.json({
      checkedInCount: (checkedInRows || []).length,
      totalActiveStaff: totalActive || 0
    });
  } catch (err) {
    console.error('[ATTENDANCE-SUMMARY-ERROR]', err);
    return res.status(500).json({ error: 'Could not load attendance summary.' });
  }
});

// GET /api/attendance/my-history?limit=N -- personal attendance history,
// regular staff only (field staff have no account to view this from).
router.get('/api/attendance/my-history', async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 14, 90);

  try {
    const { data, error } = await supabase
      .from('attendance_logs')
      .select('log_date, check_in_time, check_out_time')
      .eq('staff_ref_id', req.session.staff.id)
      .order('log_date', { ascending: false })
      .limit(limit);

    if (error) throw error;

    return res.json({ history: data || [] });
  } catch (err) {
    console.error('[ATTENDANCE-MY-HISTORY-ERROR]', err);
    return res.status(500).json({ error: 'Could not load your attendance history.' });
  }
});

module.exports = router;
