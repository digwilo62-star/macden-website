const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// GET /api/accounting/staff?search=amara — searchable directory, excludes yourself
router.get('/', async (req, res) => {
  const search = (req.query.search || '').trim();

  let query = supabase
    .from('staff')
    .select('id, full_name, username')
    .eq('is_active', true)
    .neq('id', req.session.staff.id)
    .order('full_name', { ascending: true });

  if (search) {
    query = query.or(`full_name.ilike.%${search}%,username.ilike.%${search}%`);
  }

  const { data, error } = await query;

  if (error) {
    return res.status(500).json({ error: 'Could not load staff directory.' });
  }

  res.json({ staff: data });
});

module.exports = router;

