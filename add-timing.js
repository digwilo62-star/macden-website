const fs = require('fs');
const filePath = 'server/routes/auth.js';

const raw = fs.readFileSync(filePath, 'utf8');
const usesCRLF = raw.includes('\r\n');
let content = raw.replace(/\r\n/g, '\n');

const oldBlock = `router.post('/login', authLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Email and password are required.' });
    }
    const isEmail = username.includes('@');
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, email_verified, department_id, must_change_password, mfa_enabled, photo_url')
      .eq(isEmail ? 'email' : 'username', username)
      .single();
    if (error || !staffMember) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }
    const passwordMatches = await bcrypt.compare(password, staffMember.password_hash);
    if (!passwordMatches) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }`;

const newBlock = `router.post('/login', authLimiter, async (req, res) => {
  const __t0 = Date.now();
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'Email and password are required.' });
    }
    const isEmail = username.includes('@');
    const { data: staffMember, error } = await supabase
      .from('staff')
      .select('id, full_name, username, password_hash, role, can_edit_prices, is_active, email_verified, department_id, must_change_password, mfa_enabled, photo_url')
      .eq(isEmail ? 'email' : 'username', username)
      .single();
    console.log('[LOGIN TIMING] staff lookup took ' + (Date.now() - __t0) + 'ms');
    if (error || !staffMember) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }
    const __t1 = Date.now();
    const passwordMatches = await bcrypt.compare(password, staffMember.password_hash);
    console.log('[LOGIN TIMING] bcrypt compare took ' + (Date.now() - __t1) + 'ms');
    if (!passwordMatches) {
      return res.status(401).json({ error: 'Invalid email or password.' });
    }`;

if (content.includes('[LOGIN TIMING]')) {
  console.log('Already instrumented.');
  process.exit(0);
}
if (!content.includes(oldBlock)) {
  console.error('ERROR: exact block not found. Nothing changed.');
  process.exit(1);
}
content = content.replace(oldBlock, newBlock);

const oldRegen = `    req.session.regenerate((regenErr) => {
      if (regenErr) {
        console.error('Session regenerate error:', regenErr);
        return res.status(500).json({ error: 'Something went wrong logging you in.' });
      }
      req.session.staff = {`;

const newRegen = `    const __t2 = Date.now();
    req.session.regenerate((regenErr) => {
      console.log('[LOGIN TIMING] session.regenerate took ' + (Date.now() - __t2) + 'ms');
      if (regenErr) {
        console.error('Session regenerate error:', regenErr);
        return res.status(500).json({ error: 'Something went wrong logging you in.' });
      }
      req.session.staff = {`;

if (!content.includes(oldRegen)) {
  console.error('ERROR: regenerate block not found. Nothing changed for that part.');
  process.exit(1);
}
content = content.replace(oldRegen, newRegen);

const out = usesCRLF ? content.replace(/\n/g, '\r\n') : content;
fs.writeFileSync(filePath, out);
console.log('Timing instrumentation added to /login.');
