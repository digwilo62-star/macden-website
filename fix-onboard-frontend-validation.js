// Fixes the frontend's OWN validation check, which still required
// departmentId even after the backend and dropdown were fixed. This is
// exactly what was blocking submission with the old error message.
//
//   node fix-onboard-frontend-validation.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'onboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');

if (content.includes("if (!fullName || !email || !role) {\n        showAlert")) {
  console.log('Already fixed, skipping.');
  process.exit(0);
}

const oldCheck = `if (!fullName || !email || !role || !departmentId) {
        showAlert(alertEl, 'Full name, email, role, and department are required.');
        goToStep(1);
        return;
      }`;

const newCheck = `if (!fullName || !email || !role) {
        showAlert(alertEl, 'Full name, email, and role are required.');
        goToStep(1);
        return;
      }`;

if (content.includes(oldCheck)) {
  content = content.replace(oldCheck, newCheck);
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('Fixed: frontend validation no longer requires Department.');
} else {
  console.log('WARNING: could not find the expected validation block. Nothing changed -- paste back your current onboard.html.');
  process.exit(1);
}

