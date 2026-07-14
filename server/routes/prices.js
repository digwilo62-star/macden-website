const express = require('express');
const supabase = require('../config/supabaseClient');

const router = express.Router();

function requireCanEditPrices(req, res, next) {
  if (!req.session.staff.canEditPrices) {
    return res.status(403).json({ error: 'You do not have permission to edit prices.' });
  }
  next();
}

// GET /api/accounting/prices — everyone can read
router.get('/', async (req, res) => {
  const { data, error } = await supabase
    .from('accounting_prices')
    .select('id, product_name, cost_price, margin_percent, updated_at')
    .order('product_name', { ascending: true });

  if (error) {
    return res.status(500).json({ error: 'Could not load prices.' });
  }

  res.json({ prices: data });
});

// POST /api/accounting/prices — add a new product price (editors only)
router.post('/', requireCanEditPrices, async (req, res) => {
  const { productName, costPrice, marginPercent } = req.body;

  if (!productName || costPrice === undefined) {
    return res.status(400).json({ error: 'Product name and cost price are required.' });
  }

  const { data, error } = await supabase
    .from('accounting_prices')
    .insert({
      product_name: productName,
      cost_price: costPrice,
      margin_percent: marginPercent || null,
      updated_by: req.session.staff.id
    })
    .select()
    .single();

  if (error) {
    return res.status(400).json({ error: 'Could not add product. It may already exist.' });
  }

  res.json({ success: true, price: data });
});

// PUT /api/accounting/prices/:id — update a price (editors only)
// Snapshots the OLD value into history before overwriting, so "last week / last month" stays accurate.
router.put('/:id', requireCanEditPrices, async (req, res) => {
  const { id } = req.params;
  const { costPrice, marginPercent } = req.body;

  if (costPrice === undefined) {
    return res.status(400).json({ error: 'Cost price is required.' });
  }

  const { data: existing, error: fetchError } = await supabase
    .from('accounting_prices')
    .select('cost_price, margin_percent')
    .eq('id', id)
    .single();

  if (fetchError || !existing) {
    return res.status(404).json({ error: 'Product not found.' });
  }

  // Snapshot the value being replaced, so history reflects what the price WAS
  const { error: historyError } = await supabase
    .from('accounting_price_history')
    .insert({
      price_id: id,
      cost_price: existing.cost_price,
      margin_percent: existing.margin_percent,
      recorded_by: req.session.staff.id
    });

  if (historyError) {
    return res.status(500).json({ error: 'Could not save price history.' });
  }

  const { data: updated, error: updateError } = await supabase
    .from('accounting_prices')
    .update({
      cost_price: costPrice,
      margin_percent: marginPercent || null,
      updated_by: req.session.staff.id,
      updated_at: new Date().toISOString()
    })
    .eq('id', id)
    .select()
    .single();

  if (updateError) {
    return res.status(500).json({ error: 'Could not update price.' });
  }

  res.json({ success: true, price: updated });
});

// GET /api/accounting/prices/:id/history?range=week|month — everyone can read
router.get('/:id/history', async (req, res) => {
  const { id } = req.params;
  const range = req.query.range === 'month' ? 30 : 7; // default to last week

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - range);

  const { data, error } = await supabase
    .from('accounting_price_history')
    .select('id, cost_price, margin_percent, recorded_at')
    .eq('price_id', id)
    .gte('recorded_at', cutoff.toISOString())
    .order('recorded_at', { ascending: false });

  if (error) {
    return res.status(500).json({ error: 'Could not load price history.' });
  }

  res.json({ history: data });
});

module.exports = router;

