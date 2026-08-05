// Adds Department (dropdown, populated live), Branch, and Phone Number
// fields to the registration form, and sends them to the backend.
//
//   node fix-register-frontend.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'register.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add the new fields to the form, right after Username ----
const usernameFieldRegex = /<div class="field">\s*<label for="username">Username<\/label>\s*<input[^>]*id="username"[^>]*>\s*<\/div>/;

const newFields = `<div class="field">
            <label for="username">Username</label>
            <input type="text" id="username" name="username" required>
          </div>
          <div class="field">
            <label for="department">Department</label>
            <select id="department" name="department" required>
              <option value="">Select your department…</option>
            </select>
          </div>
          <div class="field">
            <label for="branch">Branch</label>
            <input type="text" id="branch" name="branch" placeholder="e.g. Ikeja Branch">
          </div>
          <div class="field">
            <label for="phone">Phone Number</label>
            <input type="tel" id="phone" name="phone" placeholder="0801 234 5678">
          </div>`;

if (usernameFieldRegex.test(content) && !content.includes('id="department"')) {
  content = content.replace(usernameFieldRegex, newFields);
  changed = true;
  console.log('Added Department, Branch, and Phone Number fields.');
} else if (content.includes('id="department"')) {
  console.log('Fields already present, skipping that part.');
} else {
  console.log('WARNING: could not find the Username field. Nothing changed for that part -- paste back register.html again if this persists.');
}

// ---- 2. Load real departments into the dropdown on page load ----
if (!content.includes('async function loadDepartments')) {
  const scriptOpenAnchor = '<script>';
  const loadDeptFn = `<script>
    async function loadDepartments() {
      try {
        const res = await fetch('/api/accounting/auth/departments');
        const data = await res.json();
        const select = document.getElementById('department');
        (data.departments || []).forEach(d => {
          const opt = document.createElement('option');
          opt.value = d.id;
          opt.textContent = d.name;
          select.appendChild(opt);
        });
      } catch (err) {
        // If this fails, the dropdown just stays on "Select your department…" --
        // registration will correctly block submission until they pick one
      }
    }
    loadDepartments();
`;
  content = content.replace(scriptOpenAnchor, loadDeptFn);
  changed = true;
  console.log('Added loadDepartments() to populate the dropdown.');
} else {
  console.log('loadDepartments() already present, skipping that part.');
}

// ---- 3. Send the new fields when submitting ----
const oldSubmit = `body: {
            fullName: document.getElementById('fullName').value.trim(),
            username: document.getElementById('username').value.trim(),
            email: document.getElementById('email').value.trim(),
            password: document.getElementById('password').value
          }`;

const newSubmit = `body: {
            fullName: document.getElementById('fullName').value.trim(),
            username: document.getElementById('username').value.trim(),
            email: document.getElementById('email').value.trim(),
            password: document.getElementById('password').value,
            departmentId: document.getElementById('department').value,
            branch: document.getElementById('branch').value.trim(),
            phone: document.getElementById('phone').value.trim()
          }`;

if (content.includes(oldSubmit)) {
  content = content.replace(oldSubmit, newSubmit);
  changed = true;
  console.log('Updated form submission to include the new fields.');
} else if (content.includes('departmentId: document.getElementById')) {
  console.log('Submission already updated, skipping that part.');
} else {
  console.log('WARNING: could not find the expected submit body. Nothing changed for that part -- paste back register.html again if this persists.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nregister.html patched successfully.');
}

