// Combines two changes to the login page:
// 1. Label fix -- "Email" -> "Username or Email" (the backend has always
//    accepted both, the label just never said so)
// 2. Show/hide password toggle -- an eye icon that reveals the password
//    as plain text when clicked, and hides it again on a second click.
//
//   node fix-login-label-and-eye.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'login.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Label fix ----
const oldField = `<label for="email">Email</label>
            <input type="text" id="email" name="email" placeholder="name@macden.com" required>`;
const newField = `<label for="email">Username or Email</label>
            <input type="text" id="email" name="email" placeholder="Your username or email" required>`;

if (content.includes(oldField)) {
  content = content.replace(oldField, newField);
  changed = true;
  console.log('Fixed: login form now clearly accepts username or email.');
} else if (content.includes('Username or Email')) {
  console.log('Label already fixed, skipping that part.');
}

// ---- 2. Eye icon toggle for the password field ----
const oldPasswordField = `<label for="password">Password</label>
            <input type="password" id="password" name="password" placeholder="••••••••" required>`;

const newPasswordField = `<label for="password">Password</label>
            <div style="position:relative;">
              <input type="password" id="password" name="password" placeholder="••••••••" required style="padding-right:42px; width:100%; box-sizing:border-box;">
              <button type="button" id="togglePasswordBtn" aria-label="Show password" style="position:absolute; right:10px; top:50%; transform:translateY(-50%); background:none; border:none; cursor:pointer; color:var(--text-muted); padding:4px; display:flex; align-items:center;">
                <i class="ti ti-eye" id="togglePasswordIcon"></i>
              </button>
            </div>`;

if (content.includes(oldPasswordField)) {
  content = content.replace(oldPasswordField, newPasswordField);
  changed = true;
  console.log('Added show/hide password toggle (eye icon).');
} else if (content.includes('togglePasswordBtn')) {
  console.log('Eye icon already present, skipping that part.');
} else {
  console.log('WARNING: could not find the expected password field. Nothing changed for that part -- paste back your current login.html.');
}

// ---- 3. The actual toggle logic ----
if (!content.includes("getElementById('togglePasswordBtn')")) {
  const scriptAnchor = 'form.addEventListener';
  const toggleScript = `document.getElementById('togglePasswordBtn').addEventListener('click', () => {
      const input = document.getElementById('password');
      const icon = document.getElementById('togglePasswordIcon');
      if (input.type === 'password') {
        input.type = 'text';
        icon.className = 'ti ti-eye-off';
      } else {
        input.type = 'password';
        icon.className = 'ti ti-eye';
      }
    });

    `;
  if (content.includes(scriptAnchor)) {
    content = content.replace(scriptAnchor, toggleScript + scriptAnchor);
    changed = true;
    console.log('Wired up the toggle click behavior.');
  } else {
    console.log('WARNING: could not find a good anchor for the toggle script. Nothing changed for that part.');
  }
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nlogin.html patched successfully.');
} else {
  console.log('\nNo changes made -- everything already present.');
}

