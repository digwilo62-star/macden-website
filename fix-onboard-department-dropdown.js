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

