const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// POST /api/accounting/presence/heartbeat
// Called every ~20 seconds by the frontend while a page is open.
// Anyone whose last_seen is within the last 40 seconds counts as online.
router.post('/heartbeat', async (req, res) => {
  try {
    await supabase
      .from('staff')
      .update({ last_seen: new Date().toISOString() })
      .eq('id', req.session.staff.id);

    res.json({ success: true });
  } catch (err) {
    console.error('Heartbeat unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

module.exports = router;

