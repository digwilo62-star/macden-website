#!/usr/bin/env bash
# Makes Department optional in onboarding -- adds a 'None' option to
# the dropdown (for roles like HR that aren't tied to one specific
# operational department), and removes the backend requirement. Empty
# department correctly stores as a real NULL, not an empty string.
# RUN THE SQL MIGRATION FIRST in Supabase before running this script.
set -e
cat > fix-onboard-department-optional.js << 'EOF_BACKEND_JS'
// Makes Department optional in onboarding -- needed for roles like HR that
// aren't tied to one specific operational department.
//
//   node fix-onboard-department-optional.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'server', 'routes', 'admin.js');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

const oldCheck = `if (!fullName || !email || !role || !departmentId) {
      return res.status(400).json({ error: 'Full name, email, role, and department are required.' });
    }`;
const newCheck = `if (!fullName || !email || !role) {
      return res.status(400).json({ error: 'Full name, email, and role are required.' });
    }`;

if (content.includes(newCheck)) {
  console.log('Already fixed, skipping.');
  process.exit(0);
}

if (content.includes(oldCheck)) {
  content = content.replace(oldCheck, newCheck);
} else {
  console.log('WARNING: could not find the expected validation check. Nothing changed for that part -- paste back your current admin.js.');
  process.exit(1);
}

// Also make sure an empty departmentId gets stored as a real NULL, not an
// empty string (which Postgres would reject for a uuid column)
const oldInsertField = 'department_id: departmentId,';
const newInsertField = 'department_id: departmentId || null,';

if (content.includes(oldInsertField)) {
  content = content.replace(oldInsertField, newInsertField);
  console.log('Fixed: empty department now stores as NULL, not an empty string.');
} else if (content.includes(newInsertField)) {
  console.log('Insert field already handles empty department correctly, skipping that part.');
} else {
  console.log('NOTE: could not find the exact department_id insert line -- may need a manual check if this causes a database error.');
}

fs.writeFileSync(filePath, content, 'utf8');
console.log('\nadmin.js patched successfully: Department is now optional for onboarding.');

EOF_BACKEND_JS
cat > fix-onboard-department-dropdown.js << 'EOF_FRONTEND_JS'
// Adds a "None" option to the Department dropdown in onboarding.
//
//   node fix-onboard-department-dropdown.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'onboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes("'<option value=\"\">None</option>'")) {
  console.log('Already fixed, skipping.');
  process.exit(0);
}

const oldPopulate = `document.getElementById('departmentId').innerHTML = result.departments.map(d =>'<option value="' + d.id + '">' + d.name + '</option>').join('');`;
const newPopulate = `document.getElementById('departmentId').innerHTML = '<option value="">None</option>' + result.departments.map(d =>'<option value="' + d.id + '">' + d.name + '</option>').join('');`;

if (content.includes(oldPopulate)) {
  content = content.replace(oldPopulate, newPopulate);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Fixed: Department dropdown now includes a None option.');
} else {
  console.log('WARNING: could not find the expected line. Nothing changed -- paste back your current onboard.html.');
  process.exit(1);
}

// Also update the "Department *" label to drop the asterisk, since it's no longer strictly required
const oldLabel = '<label>Department *</label>';
const newLabel = '<label>Department</label>';
if (content.includes(oldLabel)) {
  let c2 = fs.readFileSync(filePath, 'utf8');
  c2 = c2.replace(oldLabel, newLabel);
  fs.writeFileSync(filePath, c2, 'utf8');
  console.log('Updated label to remove the required-field asterisk.');
}

EOF_FRONTEND_JS
echo "Running both patchers..."
node fix-onboard-department-optional.js
node fix-onboard-department-dropdown.js
echo "Done. Restart your server."