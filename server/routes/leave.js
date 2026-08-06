const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function daysBetween(startDate, endDate) {
  const start = new Date(startDate);
  const end = new Date(endDate);
  const diffMs = end - start;
  return Math.round(diffMs / (1000 * 60 * 60 * 24)) + 1; // inclusive of both days
}

// POST /api/accounting/leave — submit a new leave request
router.post('/', async (req, res) => {
  try {
    const { leaveType, startDate, endDate, reason } = req.body;
    const staffId = req.session.staff.id;

    if (!leaveType || !startDate || !endDate) {
      return res.status(400).json({ error: 'Leave type, start date, and end date are required.' });
    }

    if (new Date(endDate) < new Date(startDate)) {
      return res.status(400).json({ error: 'End date cannot be before start date.' });
    }

    const { data, error } = await supabase
      .from('leave_requests')
      .insert({
        staff_id: staffId,
        leave_type: leaveType,
        start_date: startDate,
        end_date: endDate,
        reason: reason || null,
        status: 'pending'
      })
      .select()
      .single();

    if (error) {
      console.error('Leave request insert error:', error);
      return res.status(500).json({ error: 'Could not submit leave request.' });
    }

    res.json({ success: true, request: data });
  } catch (err) {
    console.error('Leave submit unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong submitting your request.' });
  }
});

// GET /api/accounting/leave/mine — this staff member's own requests
router.get('/mine', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('leave_requests')
      .select('id, leave_type, start_date, end_date, reason, status, requested_at')
      .eq('staff_id', req.session.staff.id)
      .order('requested_at', { ascending: false });

    if (error) {
      console.error('Leave mine fetch error:', error);
      return res.status(500).json({ error: 'Could not load your requests.' });
    }

    const withDays = data.map(r => ({ ...r, days: daysBetween(r.start_date, r.end_date) }));
    res.json({ requests: withDays });
  } catch (err) {
    console.error('Leave mine unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading your requests.' });
  }
});

// GET /api/accounting/leave/pending — admin-only, everyone's pending requests
router.get('/pending', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view pending approvals.' });
    }

    const { data, error } = await supabase
      .from('leave_requests')
      .select('id, staff_id, leave_type, start_date, end_date, reason, status, requested_at')
      .eq('status', 'pending')
      .order('requested_at', { ascending: true });

    if (error) {
      console.error('Leave pending fetch error:', error);
      return res.status(500).json({ error: 'Could not load pending requests.' });
    }

    const staffIds = [...new Set(data.map(r => r.staff_id))];
    const { data: staffRows } = await supabase
      .from('staff')
      .select('id, full_name, username, is_active')
      .in('id', staffIds.length > 0 ? staffIds : ['00000000-0000-0000-0000-000000000000']);
    const staffById = {};
    (staffRows || []).forEach(s => { staffById[s.id] = s; });

    const enriched = data.map(r => ({
      ...r,
      days: daysBetween(r.start_date, r.end_date),
      staffName: staffById[r.staff_id] ? staffById[r.staff_id].full_name : 'Unknown',
      staffUsername: staffById[r.staff_id] ? staffById[r.staff_id].username : '',
      staffIsActive: staffById[r.staff_id] ? staffById[r.staff_id].is_active : true
    }));

    res.json({ requests: enriched });
  } catch (err) {
    console.error('Leave pending unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading pending requests.' });
  }
});

// POST /api/accounting/leave/:id/approve — admin-only
router.post('/:id/approve', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can approve requests.' });
    }

    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'approved', reviewed_by: req.session.staff.id, reviewed_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not approve this request.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Leave approve unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// POST /api/accounting/leave/:id/reject — admin-only
router.post('/:id/reject', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can reject requests.' });
    }

    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'rejected', reviewed_by: req.session.staff.id, reviewed_at: new Date().toISOString() })
      .eq('id', req.params.id);

    if (error) {
      return res.status(500).json({ error: 'Could not reject this request.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Leave reject unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

// GET /api/accounting/leave/stats — admin-only, last 30 days summary
router.get('/stats', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can view stats.' });
    }

    const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await supabase
      .from('leave_requests')
      .select('status, requested_at, reviewed_at')
      .not('reviewed_at', 'is', null)
      .gte('reviewed_at', thirtyDaysAgo);

    if (error) {
      console.error('Leave stats fetch error:', error);
      return res.status(500).json({ error: 'Could not load leave stats.' });
    }

    const approvedCount = data.filter(r => r.status === 'approved').length;
    const rejectedCount = data.filter(r => r.status === 'rejected').length;

    let avgTurnaroundHours = null;
    if (data.length > 0) {
      const totalHours = data.reduce((sum, r) => {
        const hours = (new Date(r.reviewed_at) - new Date(r.requested_at)) / (1000 * 60 * 60);
        return sum + hours;
      }, 0);
      avgTurnaroundHours = Math.round(totalHours / data.length);
    }

    res.json({ approvedCount, rejectedCount, avgTurnaroundHours });
  } catch (err) {
    console.error('Leave stats unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading leave stats.' });
  }
});

module.exports = router;

