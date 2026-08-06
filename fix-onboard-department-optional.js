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

