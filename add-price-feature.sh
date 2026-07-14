#!/usr/bin/env bash
# Adds price-check + price-history feature (backend routes + frontend pages).
# Run this from the ROOT of your macden-website repo, in Git Bash.
set -e

mkdir -p server/routes accounting

cat > server/routes/prices.js << 'EOF_SERVER_ROUTES_PRICES_JS'
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

EOF_SERVER_ROUTES_PRICES_JS

cat > server/server.js << 'EOF_SERVER_SERVER_JS'
require('dotenv').config();

const path = require('path');
const express = require('express');
const session = require('express-session');
const cors = require('cors');

const authRoutes = require('./routes/auth');
const adminRoutes = require('./routes/admin');
const priceRoutes = require('./routes/prices');
const requireAuth = require('./middleware/requireAuth');

const app = express();

app.use(express.json());

// CORS — allow requests from your actual site only.
// If the accounting pages are served from the same domain (macden.com.ng/accounting),
// this can be tightened further. Update the origin below to match your real domain.
app.use(cors({
  origin: 'https://macden.com.ng',
  credentials: true
}));

app.use(session({
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production', // HTTPS required only in production
    sameSite: 'lax',
    maxAge: 1000 * 60 * 60 * 8   // 8-hour session, adjust as needed
  }
}));

// Serve the accounting frontend pages (login, register, dashboard, etc.)
// Lives in a sibling folder: macden-website/accounting
app.use('/accounting', express.static(path.join(__dirname, '../accounting')));

// Health check — useful for confirming Render deploy is alive
app.get('/api/accounting/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Auth routes (login/logout/me) — not behind requireAuth, obviously
app.use('/api/accounting/auth', authRoutes);

// Everything below this line will require a logged-in session.
// Placeholder for now — Phase 3 (prices) and Phase 4 (messaging)
// routes will be added here as we build them.
app.use('/api/accounting', requireAuth);
app.use('/api/accounting/admin', adminRoutes);
app.use('/api/accounting/prices', priceRoutes);

app.get('/api/accounting/dashboard-check', (req, res) => {
  // Simple proof that requireAuth is working — returns the logged-in staff's info
  res.json({ message: `Welcome, ${req.session.staff.fullName}`, staff: req.session.staff });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Accounting backend running on port ${PORT}`);
});

EOF_SERVER_SERVER_JS

cat > accounting/prices.html << 'EOF_ACCOUNTING_PRICES_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Price check — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .price-table {
      width: 100%;
      border-collapse: collapse;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-md);
      overflow: hidden;
    }
    .price-table th {
      text-align: left;
      font-size: 11.5px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      color: var(--text-secondary);
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      background: var(--surface-raised);
    }
    .price-table td {
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      font-size: 13.5px;
    }
    .price-table tr:last-child td { border-bottom: none; }
    .price-table .mono { font-family: var(--font-mono); color: var(--text-secondary); font-size: 12.5px; }
    .edit-inline-btn {
      background: transparent;
      border: 1px solid var(--border);
      color: var(--text-secondary);
      font-size: 12px;
      padding: 5px 10px;
      border-radius: var(--radius-sm);
      cursor: pointer;
      font-family: var(--font-ui);
    }
    .edit-inline-btn:hover { border-color: var(--accent-green); color: var(--accent-green); }
    .toolbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
    }
    .add-btn {
      width: auto;
      padding: 9px 16px;
    }
    /* Simple modal */
    .modal-backdrop {
      display: none;
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.6);
      align-items: center;
      justify-content: center;
      z-index: 100;
    }
    .modal-backdrop.visible { display: flex; }
    .modal {
      width: 360px;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-lg);
      padding: 24px;
    }
    .modal h3 { margin: 0 0 16px; font-size: 15px; }
    .modal-actions { display: flex; gap: 8px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <div class="topbar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </div>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <div class="toolbar">
        <div>
          <h1 class="page-title">Price check</h1>
          <p class="page-subtitle">Current product pricing. <a href="prices-history.html" style="color: var(--accent-green);">View history →</a></p>
        </div>
        <button class="btn btn-primary add-btn" id="addBtn" style="display: none;">+ Add product</button>
      </div>

      <div id="alert" class="alert alert-error"></div>

      <table class="price-table">
        <thead>
          <tr>
            <th>Product</th>
            <th>Cost price</th>
            <th>Margin</th>
            <th>Last updated</th>
            <th></th>
          </tr>
        </thead>
        <tbody id="priceTableBody">
          <tr><td colspan="5" class="pending-loading">Loading prices…</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- Edit / Add modal -->
  <div class="modal-backdrop" id="modalBackdrop">
    <div class="modal">
      <h3 id="modalTitle">Edit price</h3>
      <div id="modalAlert" class="alert alert-error"></div>
      <div class="field" id="productNameField" style="display: none;">
        <label>Product name</label>
        <input type="text" id="modalProductName" placeholder="e.g. Guinness Stout 60cl">
      </div>
      <div class="field">
        <label>Cost price (₦)</label>
        <input type="number" id="modalCostPrice" step="0.01" placeholder="0.00">
      </div>
      <div class="field">
        <label>Margin (%)</label>
        <input type="number" id="modalMargin" step="0.1" placeholder="Optional">
      </div>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="modalCancel">Cancel</button>
        <button class="btn btn-primary" id="modalSave">Save</button>
      </div>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let canEdit = false;
    let editingId = null;

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
        canEdit = result.staff.canEditPrices;
        if (canEdit) document.getElementById('addBtn').style.display = 'block';
        loadPrices();
      } catch (err) {
        window.location.href = 'login.html';
      }
    }

    async function loadPrices() {
      const tbody = document.getElementById('priceTableBody');
      try {
        const result = await apiRequest('/prices');
        if (result.prices.length === 0) {
          tbody.innerHTML = '<tr><td colspan="5" class="pending-loading">No products yet.</td></tr>';
          return;
        }
        tbody.innerHTML = result.prices.map(p => `
          <tr>
            <td>${p.product_name}</td>
            <td class="mono">₦${Number(p.cost_price).toLocaleString()}</td>
            <td class="mono">${p.margin_percent ? p.margin_percent + '%' : '—'}</td>
            <td class="mono">${new Date(p.updated_at).toLocaleDateString()}</td>
            <td>${canEdit ? `<button class="edit-inline-btn" onclick="openEdit('${p.id}', '${p.product_name}', ${p.cost_price}, ${p.margin_percent || 'null'})">Edit</button>` : ''}</td>
          </tr>
        `).join('');
      } catch (err) {
        tbody.innerHTML = `<tr><td colspan="5" class="pending-loading">Could not load prices.</td></tr>`;
      }
    }

    const modalBackdrop = document.getElementById('modalBackdrop');
    const modalAlert = document.getElementById('modalAlert');

    function openEdit(id, name, cost, margin) {
      editingId = id;
      document.getElementById('modalTitle').textContent = `Edit — ${name}`;
      document.getElementById('productNameField').style.display = 'none';
      document.getElementById('modalCostPrice').value = cost;
      document.getElementById('modalMargin').value = margin || '';
      hideAlert(modalAlert);
      modalBackdrop.classList.add('visible');
    }

    document.getElementById('addBtn').addEventListener('click', () => {
      editingId = null;
      document.getElementById('modalTitle').textContent = 'Add product';
      document.getElementById('productNameField').style.display = 'block';
      document.getElementById('modalProductName').value = '';
      document.getElementById('modalCostPrice').value = '';
      document.getElementById('modalMargin').value = '';
      hideAlert(modalAlert);
      modalBackdrop.classList.add('visible');
    });

    document.getElementById('modalCancel').addEventListener('click', () => {
      modalBackdrop.classList.remove('visible');
    });

    document.getElementById('modalSave').addEventListener('click', async () => {
      const costPrice = parseFloat(document.getElementById('modalCostPrice').value);
      const marginPercent = document.getElementById('modalMargin').value
        ? parseFloat(document.getElementById('modalMargin').value)
        : null;

      if (isNaN(costPrice)) {
        showAlert(modalAlert, 'Enter a valid cost price.');
        return;
      }

      try {
        if (editingId) {
          await apiRequest(`/prices/${editingId}`, {
            method: 'PUT',
            body: { costPrice, marginPercent }
          });
        } else {
          const productName = document.getElementById('modalProductName').value.trim();
          if (!productName) {
            showAlert(modalAlert, 'Enter a product name.');
            return;
          }
          await apiRequest('/prices', {
            method: 'POST',
            body: { productName, costPrice, marginPercent }
          });
        }
        modalBackdrop.classList.remove('visible');
        loadPrices();
      } catch (err) {
        showAlert(modalAlert, err.message);
      }
    });

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_PRICES_HTML

cat > accounting/prices-history.html << 'EOF_ACCOUNTING_PRICES-HISTORY_HTML'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Price history — MACDEN Accounting</title>
  <link rel="stylesheet" href="assets/style.css">
  <style>
    .price-table {
      width: 100%;
      border-collapse: collapse;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: var(--radius-md);
      overflow: hidden;
    }
    .price-table th {
      text-align: left;
      font-size: 11.5px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.03em;
      color: var(--text-secondary);
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      background: var(--surface-raised);
    }
    .price-table td {
      padding: 12px 16px;
      border-bottom: 1px solid var(--border);
      font-size: 13.5px;
    }
    .price-table tr:last-child td { border-bottom: none; }
    .price-table .mono { font-family: var(--font-mono); color: var(--text-secondary); font-size: 12.5px; }

    .controls-row {
      display: flex;
      gap: 12px;
      align-items: flex-end;
      margin-bottom: 20px;
    }
    .controls-row .field { margin-bottom: 0; flex: 1; }
    .controls-row select {
      width: 100%;
      background: var(--bg);
      border: 1px solid var(--border);
      border-radius: var(--radius-sm);
      padding: 10px 12px;
      color: var(--text-primary);
      font-size: 13.5px;
      font-family: var(--font-ui);
    }
    .range-toggle {
      display: flex;
      gap: 6px;
    }
    .range-btn {
      background: transparent;
      border: 1px solid var(--border);
      color: var(--text-secondary);
      font-size: 12.5px;
      padding: 9px 14px;
      border-radius: var(--radius-sm);
      cursor: pointer;
      font-family: var(--font-ui);
    }
    .range-btn.active {
      background: var(--accent-green-dim);
      border-color: var(--accent-green);
      color: var(--accent-green);
    }
  </style>
</head>
<body>
  <div class="app-shell">
    <div class="app-topbar">
      <div class="topbar-brand">
        <img src="assets/logo.jpeg" alt="MACDEN">
        <span>MACDEN Accounting</span>
      </div>
      <div class="topbar-user">
        <span class="role-badge" id="roleBadge">—</span>
        <span class="user-name" id="userName">Loading…</span>
        <button class="logout-btn" id="logoutBtn">Log out</button>
      </div>
    </div>

    <div class="hamburger-nav" id="hamburgerNav">
      <button class="hamburger-toggle" id="hamburgerToggle" aria-label="Toggle menu">☰</button>
      <div class="hamburger-content">
        <a href="inbox.html" class="inbox-link">
          <span>Inbox</span>
          <span class="unread-badge" id="unreadBadge">0</span>
        </a>
      </div>
    </div>

    <div class="app-main" id="appMain">
      <h1 class="page-title">Price history</h1>
      <p class="page-subtitle"><a href="prices.html" style="color: var(--accent-green);">← Back to current prices</a></p>

      <div class="controls-row">
        <div class="field">
          <label>Product</label>
          <select id="productSelect">
            <option value="">Select a product…</option>
          </select>
        </div>
        <div class="range-toggle">
          <button class="range-btn active" data-range="week" id="rangeWeek">Last week</button>
          <button class="range-btn" data-range="month" id="rangeMonth">Last month</button>
        </div>
      </div>

      <table class="price-table">
        <thead>
          <tr>
            <th>Cost price</th>
            <th>Margin</th>
            <th>Recorded</th>
          </tr>
        </thead>
        <tbody id="historyTableBody">
          <tr><td colspan="3" class="pending-loading">Select a product to view its price history.</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <script src="assets/api.js"></script>
  <script>
    const hamburgerNav = document.getElementById('hamburgerNav');
    const hamburgerToggle = document.getElementById('hamburgerToggle');
    const appMain = document.getElementById('appMain');
    hamburgerToggle.addEventListener('click', () => {
      hamburgerNav.classList.toggle('collapsed');
      appMain.classList.toggle('expanded');
    });

    document.getElementById('logoutBtn').addEventListener('click', async () => {
      await apiRequest('/auth/logout', { method: 'POST' });
      window.location.href = 'login.html';
    });

    let currentRange = 'week';

    async function init() {
      try {
        const result = await apiRequest('/dashboard-check');
        document.getElementById('userName').textContent = result.staff.fullName;
        document.getElementById('roleBadge').textContent = result.staff.role;
        loadProductList();
      } catch (err) {
        window.location.href = 'login.html';
      }
    }

    async function loadProductList() {
      const select = document.getElementById('productSelect');
      try {
        const result = await apiRequest('/prices');
        select.innerHTML = '<option value="">Select a product…</option>' +
          result.prices.map(p => `<option value="${p.id}">${p.product_name}</option>`).join('');
      } catch (err) {
        select.innerHTML = '<option value="">Could not load products</option>';
      }
    }

    document.getElementById('productSelect').addEventListener('change', loadHistory);

    document.getElementById('rangeWeek').addEventListener('click', () => setRange('week'));
    document.getElementById('rangeMonth').addEventListener('click', () => setRange('month'));

    function setRange(range) {
      currentRange = range;
      document.getElementById('rangeWeek').classList.toggle('active', range === 'week');
      document.getElementById('rangeMonth').classList.toggle('active', range === 'month');
      loadHistory();
    }

    async function loadHistory() {
      const productId = document.getElementById('productSelect').value;
      const tbody = document.getElementById('historyTableBody');

      if (!productId) {
        tbody.innerHTML = '<tr><td colspan="3" class="pending-loading">Select a product to view its price history.</td></tr>';
        return;
      }

      tbody.innerHTML = '<tr><td colspan="3" class="pending-loading">Loading…</td></tr>';

      try {
        const result = await apiRequest(`/prices/${productId}/history?range=${currentRange}`);
        if (result.history.length === 0) {
          tbody.innerHTML = `<tr><td colspan="3" class="pending-loading">No price changes in the last ${currentRange}.</td></tr>`;
          return;
        }
        tbody.innerHTML = result.history.map(h => `
          <tr>
            <td class="mono">₦${Number(h.cost_price).toLocaleString()}</td>
            <td class="mono">${h.margin_percent ? h.margin_percent + '%' : '—'}</td>
            <td class="mono">${new Date(h.recorded_at).toLocaleString()}</td>
          </tr>
        `).join('');
      } catch (err) {
        tbody.innerHTML = `<tr><td colspan="3" class="pending-loading">Could not load history.</td></tr>`;
      }
    }

    init();
  </script>
</body>
</html>

EOF_ACCOUNTING_PRICES-HISTORY_HTML

echo "Price check + price history feature added."
echo "Restart your server (Ctrl+C then npm start) to pick up the changes."