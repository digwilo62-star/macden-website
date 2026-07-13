const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// Only staff with role = 'admin' can reach these routes.
function requireAdmin(req, res, next) {
  if (req.session.staff.role !== 'admin') {
    return res.status(403).json({ error: 'Admin access only.' });
  }
  next();
}

router.use(requireAdmin);

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

module.exports = router;

