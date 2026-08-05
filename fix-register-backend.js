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

