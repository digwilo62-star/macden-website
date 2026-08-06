// Fixes ALL references to the old 'accounting' folder name in server.js,
// pointing them at the real, confirmed-existing 'portal' folder instead.
// Root cause of the ENOENT crash: an earlier fix hardcoded the old folder
// name by mistake -- but on closer look, the STATIC FILE MOUNT itself
// (which serves every CSS/JS/page) also still referenced the old name.
// This makes every reference consistent with what actually exists on disk.
//
//   node fix-portal-folder-consistency.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'server.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// Fix the static mount
const oldStatic = "express.static(path.join(__dirname, '../accounting'),";
const newStatic = "express.static(path.join(__dirname, '../portal'),";
if (content.includes(oldStatic)) {
  content = content.replace(oldStatic, newStatic);
  changed = true;
  console.log('Fixed static file mount: now points at ../portal (was ../accounting).');
} else if (content.includes(newStatic)) {
  console.log('Static mount already correct, skipping that part.');
}

// Fix my explicit /portal and /portal/ route (in case an old broken version is present)
const oldRoute = "path.join(__dirname, '../accounting/login.html')";
const newRoute = "path.join(__dirname, '../portal/login.html')";
if (content.includes(oldRoute)) {
  content = content.replace(oldRoute, newRoute);
  changed = true;
  console.log('Fixed explicit /portal route: now points at ../portal/login.html.');
} else if (content.includes(newRoute)) {
  console.log('Explicit route already correct, skipping that part.');
}

// Also check for any other stray '../accounting' reference and flag it
const remainingRefs = (content.match(/\.\.\/accounting/g) || []).length;
if (remainingRefs > 0) {
  console.log('NOTE: ' + remainingRefs + ' other reference(s) to ../accounting still remain in the file -- may need a manual look.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nserver.js patched successfully.');
} else {
  console.log('\nNo changes needed -- everything already consistent.');
}

