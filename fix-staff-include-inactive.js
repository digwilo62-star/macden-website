// Adds opt-in support for including deactivated staff in the directory
// listing -- admin-only, and only when explicitly requested via
// ?includeInactive=true. Compose/Broadcast (which call this same endpoint
// without that param) are completely unaffected -- they keep seeing only
// active staff, exactly as before.
//
//   node fix-staff-include-inactive.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'staff.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

const oldQuery = `const search = (req.query.search || '').trim();

    let query = supabase
      .from('staff')
      .select('id, full_name, username, email, role, last_seen, created_at, photo_url, departments(name)')
      .eq('is_active', true)
      .neq('id', req.session.staff.id)
      .order('full_name', { ascending: true });`;

const newQuery = `const search = (req.query.search || '').trim();
    // Only admins requesting explicitly (?includeInactive=true) see
    // deactivated staff -- Compose/Broadcast never pass this, so they keep
    // seeing active-only staff exactly as before, unaffected by this change.
    const includeInactive = req.query.includeInactive === 'true' && req.session.staff.role === 'admin';

    let query = supabase
      .from('staff')
      .select('id, full_name, username, email, role, is_active, last_seen, created_at, photo_url, departments(name)')
      .neq('id', req.session.staff.id)
      .order('full_name', { ascending: true });

    if (!includeInactive) {
      query = query.eq('is_active', true);
    }`;

if (content.includes(oldQuery)) {
  content = content.replace(oldQuery, newQuery);
  changed = true;
  console.log('Added includeInactive support to the query.');
} else if (content.includes('includeInactive')) {
  console.log('Already updated, skipping that part.');
} else {
  console.log('WARNING: could not find the expected query block. Nothing changed.');
  process.exit(1);
}

const oldMap = `const staff = data.map(s => ({
      id: s.id,
      full_name: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      department: s.departments ? s.departments.name : null,
      dateStarted: s.created_at,
      photoUrl: s.photo_url,
      isOnline: isOnline(s.last_seen)
    }));`;

const newMap = `const staff = data.map(s => ({
      id: s.id,
      full_name: s.full_name,
      username: s.username,
      email: s.email,
      role: s.role,
      department: s.departments ? s.departments.name : null,
      dateStarted: s.created_at,
      photoUrl: s.photo_url,
      isActive: s.is_active,
      isOnline: isOnline(s.last_seen)
    }));`;

if (content.includes(oldMap)) {
  content = content.replace(oldMap, newMap);
  changed = true;
  console.log('Added isActive field to the response.');
} else if (content.includes('isActive: s.is_active')) {
  console.log('isActive field already present, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nstaff.js patched successfully.');
}

