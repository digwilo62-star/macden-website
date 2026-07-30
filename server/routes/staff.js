const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

const ONLINE_THRESHOLD_MS = 40 * 1000; // last_seen within 40s counts as online

function isOnline(lastSeen) {
  if (!lastSeen) return false;
  return Date.now() - new Date(lastSeen).getTime() < ONLINE_THRESHOLD_MS;
}

// GET /api/accounting/staff?search=amara — searchable directory, excludes yourself
router.get('/', async (req, res) => {
  try {
    const search = (req.query.search || '').trim();
    // Only admins requesting explicitly (?includeInactive=true) see
    // deactivated staff -- Compose/Broadcast never pass this, so they keep
    // seeing active-only staff exactly as before, unaffected by this change.
    const includeInactive = req.query.includeInactive === 'true' && req.session.staff.role === 'admin';

    let query = supabase
      .from('staff')
      .select('id, full_name, username, email, role, is_active, last_seen, created_at, photo_url, departments(name)')
      .neq('id', req.session.staff.id)
      .order('full_name', { ascending: true });

    if (!includeInactive) {
      query = query.eq('is_active', true);
    }

    if (search) {
      query = query.or(`full_name.ilike.%${search}%,username.ilike.%${search}%`);
    }

    const { data, error } = await query;

    if (error) {
      console.error('Staff search error:', error);
      return res.status(500).json({ error: 'Could not load staff directory: ' + error.message });
    }

    const staff = data.map(s => ({
      id: s.id,
      full_name: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      department: s.departments ? s.departments.name : null,
      dateStarted: s.created_at,
      photoUrl: s.photo_url,
      isActive: s.is_active,
      isOnline: isOnline(s.last_seen)
    }));

    res.json({ staff });
  } catch (err) {
    console.error('Staff search unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading staff.' });
  }
});

// GET /api/accounting/staff/orgchart — everyone can view, no sensitive fields
router.get('/orgchart', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('staff')
      .select('id, full_name, role, reports_to, departments(name)')
      .eq('is_active', true)
      .order('full_name', { ascending: true });

    if (error) {
      console.error('Org chart fetch error:', error);
      return res.status(500).json({ error: 'Could not load the org chart.' });
    }

    const people = data.map(s => ({
      id: s.id,
      fullName: s.full_name,
      role: s.role,
      department: s.departments ? s.departments.name : null,
      reportsTo: s.reports_to
    }));

    res.json({ people });
  } catch (err) {
    console.error('Org chart unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading the org chart.' });
  }
});

module.exports = router;
module.exports.isOnline = isOnline;

