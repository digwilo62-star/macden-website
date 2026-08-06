#!/usr/bin/env bash
# v2: adds 'None' to the Department dropdown, using a whitespace-
# tolerant regex instead of an exact string match -- the exact match
# failed against your real file, likely an invisible character
# difference. This version is tolerant of spacing variations around
# the arrow function and operators.
set -e
cat > fix-onboard-department-dropdown-v2.js << 'EOF_FIXER_JS'
// v2 -- uses a whitespace-tolerant regex instead of an exact string match,
// since the exact match failed against the real file (likely an invisible
// character difference, same class of issue seen before this session).
//
//   node fix-onboard-department-dropdown-v2.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'onboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

if (content.includes("'<option value=\"\">None</option>'")) {
  console.log('Dropdown already fixed, skipping that part.');
} else {
  const populateRegex = /document\.getElementById\('departmentId'\)\.innerHTML\s*=\s*result\.departments\.map\(d\s*=>\s*'<option value="'\s*\+\s*d\.id\s*\+\s*'">'\s*\+\s*d\.name\s*\+\s*'<\/option>'\)\.join\(''\);/;

  if (populateRegex.test(content)) {
    content = content.replace(populateRegex, `document.getElementById('departmentId').innerHTML = '<option value="">None</option>' + result.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');`);
    changed = true;
    console.log('Fixed: Department dropdown now includes a None option.');
  } else {
    console.log('WARNING: regex still did not match. Nothing changed for that part.');
  }
}

const oldLabel = '<label>Department *</label>';
const newLabel = '<label>Department</label>';
if (content.includes(newLabel)) {
  console.log('Label already updated, skipping that part.');
} else if (content.includes(oldLabel)) {
  content = content.replace(oldLabel, newLabel);
  changed = true;
  console.log('Updated label to remove the required-field asterisk.');
} else {
  console.log('WARNING: could not find the Department label either.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nonboard.html patched successfully.');
} else {
  console.log('\nNo changes made.');
}

EOF_FIXER_JS
echo "Running the fix..."
node fix-onboard-department-dropdown-v2.js
echo "Done. Hard-refresh (Ctrl+F5) -- no server restart needed."