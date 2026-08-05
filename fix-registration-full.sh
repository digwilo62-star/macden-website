#!/usr/bin/env bash
# Fixes registration to match your notes: adds Department (dropdown,
# real options), Branch, and Phone Number fields. Also fixes a real
# bug found along the way -- self-registration was HARDCODED to always
# assign new staff to Accounting, regardless of what they picked. That
# broke the moment the other 4 departments were seeded earlier this
# session; nobody had actually registered since then to notice.
# Both pieces tested against real/reconstructed file content, including
# a real module-load test on the backend and a whitespace-tolerance
# test on the frontend, before being sent.
set -e
cat > fix-register-backend.js << 'EOF_BACKEND_JS'
// Fixes registration to actually use the department the person picks
// (currently hardcoded to Accounting, wrong now that 5 departments exist),
// and adds branch/phone fields. Also adds a new PUBLIC endpoint to list
// departments -- needed since someone registering isn't logged in yet, so
// the existing admin-only /admin/departments route can't be used here.
//
//   node fix-register-backend.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'auth.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add a public departments-list endpoint (no auth required) ----
if (!content.includes("router.get('/departments'")) {
  const insertAfter = "router.post('/register', authLimiter, async (req, res) => {";
  const newRoute = `// GET /api/accounting/auth/departments -- public, needed so the
// registration form (used before anyone is logged in) can show real
// department choices, not just a hardcoded one.
router.get('/departments', async (req, res) => {
  try {
    const { data, error } = await supabase.from('departments').select('id, name').order('name');
    if (error) {
      console.error('Public departments fetch error:', error);
      return res.status(500).json({ error: 'Could not load departments.' });
    }
    res.json({ departments: data });
  } catch (err) {
    console.error('Public departments unexpected error:', err);
    res.status(500).json({ error: 'Something went wrong.' });
  }
});

${insertAfter}`;
  content = content.replace(insertAfter, newRoute);
  changed = true;
  console.log('Added public GET /auth/departments endpoint.');
} else {
  console.log('Departments endpoint already present, skipping that part.');
}

// ---- 2. Fix /register to use the SELECTED department, and capture branch/phone ----
const oldRegisterBody = `const { fullName, username, email, password } = req.body;

    if (!fullName || !username || !email || !password) {
      return res.status(400).json({ error: 'All fields are required.' });
    }

    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters.' });
    }

    const { data: dept, error: deptError } = await supabase
      .from('departments')
      .select('id')
      .eq('slug', 'accounting')
      .single();

    if (deptError || !dept) {
      return res.status(500).json({ error: 'Setup error — accounting department not found.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    const { data: newStaff, error } = await supabase
      .from('staff')
      .insert({
        department_id: dept.id,
        full_name: fullName,
        username: username,
        email: email,
        password_hash: passwordHash,
        email_verified: false,
        is_active: false,
        verification_code: code,
        verification_code_expires_at: expiresAt.toISOString()
      })
      .select()
      .single();`;

const newRegisterBody = `const { fullName, username, email, password, departmentId, branch, phone } = req.body;

    if (!fullName || !username || !email || !password || !departmentId) {
      return res.status(400).json({ error: 'Name, username, email, password, and department are required.' });
    }

    if (password.length < 8) {
      return res.status(400).json({ error: 'Password must be at least 8 characters.' });
    }

    // Use the department the person actually selected, not a hardcoded one --
    // now that 5 real departments exist (Sales, Accounting, Logistics,
    // Purchases, Reconciliation), self-registration needs to respect that.
    const { data: dept, error: deptError } = await supabase
      .from('departments')
      .select('id')
      .eq('id', departmentId)
      .single();

    if (deptError || !dept) {
      return res.status(400).json({ error: 'Please select a valid department.' });
    }

    const passwordHash = await bcrypt.hash(password, 10);
    const code = generateCode();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

    const { data: newStaff, error } = await supabase
      .from('staff')
      .insert({
        department_id: dept.id,
        full_name: fullName,
        username: username,
        email: email,
        phone: phone || null,
        branch: branch || null,
        password_hash: passwordHash,
        email_verified: false,
        is_active: false,
        verification_code: code,
        verification_code_expires_at: expiresAt.toISOString()
      })
      .select()
      .single();`;

if (content.includes(oldRegisterBody)) {
  content = content.replace(oldRegisterBody, newRegisterBody);
  changed = true;
  console.log('Fixed /register to use the selected department, added branch/phone.');
} else if (content.includes('departmentId, branch, phone')) {
  console.log('Register route already updated, skipping that part.');
} else {
  console.log('WARNING: could not find the expected register body. Nothing changed for that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nauth.js patched successfully.');
}

EOF_BACKEND_JS
cat > fix-register-frontend.js << 'EOF_FRONTEND_JS'
// Adds Department (dropdown, populated live), Branch, and Phone Number
// fields to the registration form, and sends them to the backend.
//
//   node fix-register-frontend.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'register.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add the new fields to the form, right after Username ----
const usernameFieldRegex = /<div class="field">\s*<label for="username">Username<\/label>\s*<input[^>]*id="username"[^>]*>\s*<\/div>/;

const newFields = `<div class="field">
            <label for="username">Username</label>
            <input type="text" id="username" name="username" required>
          </div>
          <div class="field">
            <label for="department">Department</label>
            <select id="department" name="department" required>
              <option value="">Select your department…</option>
            </select>
          </div>
          <div class="field">
            <label for="branch">Branch</label>
            <input type="text" id="branch" name="branch" placeholder="e.g. Ikeja Branch">
          </div>
          <div class="field">
            <label for="phone">Phone Number</label>
            <input type="tel" id="phone" name="phone" placeholder="0801 234 5678">
          </div>`;

if (usernameFieldRegex.test(content) && !content.includes('id="department"')) {
  content = content.replace(usernameFieldRegex, newFields);
  changed = true;
  console.log('Added Department, Branch, and Phone Number fields.');
} else if (content.includes('id="department"')) {
  console.log('Fields already present, skipping that part.');
} else {
  console.log('WARNING: could not find the Username field. Nothing changed for that part -- paste back register.html again if this persists.');
}

// ---- 2. Load real departments into the dropdown on page load ----
if (!content.includes('async function loadDepartments')) {
  const scriptOpenAnchor = '<script>';
  const loadDeptFn = `<script>
    async function loadDepartments() {
      try {
        const res = await fetch('/api/accounting/auth/departments');
        const data = await res.json();
        const select = document.getElementById('department');
        (data.departments || []).forEach(d => {
          const opt = document.createElement('option');
          opt.value = d.id;
          opt.textContent = d.name;
          select.appendChild(opt);
        });
      } catch (err) {
        // If this fails, the dropdown just stays on "Select your department…" --
        // registration will correctly block submission until they pick one
      }
    }
    loadDepartments();
`;
  content = content.replace(scriptOpenAnchor, loadDeptFn);
  changed = true;
  console.log('Added loadDepartments() to populate the dropdown.');
} else {
  console.log('loadDepartments() already present, skipping that part.');
}

// ---- 3. Send the new fields when submitting ----
const oldSubmit = `body: {
            fullName: document.getElementById('fullName').value.trim(),
            username: document.getElementById('username').value.trim(),
            email: document.getElementById('email').value.trim(),
            password: document.getElementById('password').value
          }`;

const newSubmit = `body: {
            fullName: document.getElementById('fullName').value.trim(),
            username: document.getElementById('username').value.trim(),
            email: document.getElementById('email').value.trim(),
            password: document.getElementById('password').value,
            departmentId: document.getElementById('department').value,
            branch: document.getElementById('branch').value.trim(),
            phone: document.getElementById('phone').value.trim()
          }`;

if (content.includes(oldSubmit)) {
  content = content.replace(oldSubmit, newSubmit);
  changed = true;
  console.log('Updated form submission to include the new fields.');
} else if (content.includes('departmentId: document.getElementById')) {
  console.log('Submission already updated, skipping that part.');
} else {
  console.log('WARNING: could not find the expected submit body. Nothing changed for that part -- paste back register.html again if this persists.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nregister.html patched successfully.');
}

EOF_FRONTEND_JS
echo "Running both patchers..."
node fix-register-backend.js
node fix-register-frontend.js
echo "Done. Restart your server and hard-refresh (Ctrl+F5)."