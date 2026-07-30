// Fixes the topbar avatar changing to whoever's data was last fetched.
// Root cause: applyTopbarAvatar was triggered based on the SHAPE of any
// API response (does it have a .staff.photoUrl?), not based on WHICH
// endpoint was actually called. That's fragile -- any current or future
// endpoint returning something shaped like {staff: {...photoUrl}} would
// wrongly overwrite your own avatar with someone else's. Fixed by checking
// the request path instead, restricted to only the two endpoints that
// genuinely describe the logged-in person.
//
//   node fix-avatar-leak.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'assets', 'api.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

const oldBlock = `  if (data.staff) {
    applyTopbarAvatar(data.staff.photoUrl, data.staff.fullName);
    applyRoleBasedNav(data.staff.role);
  }
  if (data.profile) {
    applyTopbarAvatar(data.profile.photoUrl, data.profile.fullName);
  }`;

const newBlock = `  // Only apply the topbar avatar/nav from endpoints that describe the
  // CURRENTLY LOGGED IN person -- checking the request PATH here (not just
  // the response shape) is what prevents someone else's photo (e.g. from
  // viewing a staff profile in Directory) from leaking into your own
  // avatar spot.
  const isSelfInfoEndpoint = path === '/dashboard-check' || path === '/settings/me';
  if (isSelfInfoEndpoint) {
    if (data.staff) {
      applyTopbarAvatar(data.staff.photoUrl, data.staff.fullName);
      applyRoleBasedNav(data.staff.role);
    }
    if (data.profile) {
      applyTopbarAvatar(data.profile.photoUrl, data.profile.fullName);
    }
  }`;

if (content.includes(oldBlock)) {
  content = content.replace(oldBlock, newBlock);
  changed = true;
  console.log('Fixed: avatar now only updates from your own account data.');
} else if (content.includes('isSelfInfoEndpoint')) {
  console.log('Already fixed, skipping.');
} else {
  console.log('WARNING: could not find the expected block. Nothing changed.');
  process.exit(1);
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\napi.js patched successfully.');
}

