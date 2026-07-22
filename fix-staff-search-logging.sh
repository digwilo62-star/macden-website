#!/usr/bin/env bash
# Adds error logging to the staff search route so we can actually see why
# it was returning 500 with no terminal output.
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes

cat > server/routes/staff.js << 'EOF_STAFF_JS'
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

    let query = supabase
      .from('staff')
      .select('id, full_name, username, last_seen')
      .eq('is_active', true)
      .neq('id', req.session.staff.id)
      .order('full_name', { ascending: true });

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
      isOnline: isOnline(s.last_seen)
    }));

    res.json({ staff });
  } catch (err) {
    console.error('Staff search unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading staff.' });
  }
});

module.exports = router;
module.exports.isOnline = isOnline;
EOF_STAFF_JS

echo "Staff route error logging fixed."
