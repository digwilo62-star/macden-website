const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

// GET /api/accounting/policies — everyone can view
router.get('/', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('policies')
      .select('id, title, body, updated_at')
      .order('title', { ascending: true });

    if (error) {
      console.error('Policies list error:', error);
      return res.status(500).json({ error: 'Could not load policies.' });
    }

    res.json({ policies: data });
  } catch (err) {
    console.error('Policies list unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong loading policies.' });
  }
});

// POST /api/accounting/policies — admin-only, create a new policy
router.post('/', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can add policies.' });
    }

    const { title, body } = req.body;
    if (!title || !title.trim() || !body || !body.trim()) {
      return res.status(400).json({ error: 'Title and content are required.' });
    }

    const { data, error } = await supabase
      .from('policies')
      .insert({ title: title.trim(), body: body.trim(), updated_by: req.session.staff.id })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ error: 'Could not create policy.' });
    }
    res.json({ success: true, policy: data });
  } catch (err) {
    console.error('Policy create unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong creating this policy.' });
  }
});

// PUT /api/accounting/policies/:id — admin-only, edit an existing policy
router.put('/:id', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can edit policies.' });
    }

    const { title, body } = req.body;
    if (!title || !title.trim() || !body || !body.trim()) {
      return res.status(400).json({ error: 'Title and content are required.' });
    }

    const { data, error } = await supabase
      .from('policies')
      .update({ title: title.trim(), body: body.trim(), updated_by: req.session.staff.id, updated_at: new Date().toISOString() })
      .eq('id', req.params.id)
      .select()
      .single();

    if (error) {
      return res.status(500).json({ error: 'Could not update policy.' });
    }
    res.json({ success: true, policy: data });
  } catch (err) {
    console.error('Policy update unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong updating this policy.' });
  }
});

// DELETE /api/accounting/policies/:id — admin-only
router.delete('/:id', async (req, res) => {
  try {
    if (req.session.staff.role !== 'admin') {
      return res.status(403).json({ error: 'Only admins can delete policies.' });
    }

    const { error } = await supabase.from('policies').delete().eq('id', req.params.id);
    if (error) {
      return res.status(500).json({ error: 'Could not delete policy.' });
    }
    res.json({ success: true });
  } catch (err) {
    console.error('Policy delete unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong deleting this policy.' });
  }
});

module.exports = router;

