// Makes the staff directory query always exclude permanently-deleted
// accounts, regardless of the includeInactive flag -- deactivated people
// can still show up (that's the whole point of includeInactive), but
// deleted people should never appear anywhere again.
//
//   node fix-staff-exclude-deleted.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'staff.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes("is('deleted_at', null)")) {
  console.log('Already updated, skipping.');
  process.exit(0);
}

const anchor = ".neq('id', req.session.staff.id)\n      .order('full_name', { ascending: true });";
const replacement = ".neq('id', req.session.staff.id)\n      .is('deleted_at', null)\n      .order('full_name', { ascending: true });";

if (content.includes(anchor)) {
  content = content.replace(anchor, replacement);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Directory/search now excludes permanently-deleted accounts.');
} else {
  console.log('WARNING: could not find the expected query anchor. Nothing changed -- paste back staff.js if this persists.');
  process.exit(1);
}

