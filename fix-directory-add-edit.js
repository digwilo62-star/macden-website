// Adds an "Edit" button to Directory's profile modal (admin-only), opening
// a small modal to change role, department, phone, or branch. Fetches the
// person's CURRENT full record first so unrelated fields aren't
// accidentally wiped when only one thing (like role) is being changed.
//
//   node fix-directory-add-edit.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'directory.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add the Edit modal HTML (self-contained, appended once) ----
const editModalHtml = `
  <div class="modal-backdrop" id="editStaffModalBackdrop">
    <div class="modal" style="width: 380px;">
      <h3>Edit Staff Member</h3>
      <div id="editStaffAlert" class="alert alert-error"></div>
      <div style="margin-bottom:12px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Full Name</label>
        <input type="text" id="editFullName" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
      </div>
      <div style="margin-bottom:12px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Account Type</label>
        <select id="editRole" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
          <option value="staff">Staff</option>
          <option value="admin">Admin</option>
        </select>
      </div>
      <div style="margin-bottom:12px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Department</label>
        <select id="editDepartmentId" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
          <option value="">None</option>
        </select>
      </div>
      <div style="margin-bottom:12px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Phone</label>
        <input type="text" id="editPhone" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
      </div>
      <div style="margin-bottom:16px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Branch</label>
        <input type="text" id="editBranch" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
      </div>
      <div class="modal-actions">
        <button class="btn btn-ghost" id="editStaffCancelBtn">Cancel</button>
        <button class="btn btn-primary" id="editStaffSaveBtn">Save Changes</button>
      </div>
    </div>
  </div>
`;

if (!content.includes('id="editStaffModalBackdrop"')) {
  content = content.replace('<script src="assets/api.js"></script>', editModalHtml + '\n  <script src="assets/api.js"></script>');
  changed = true;
  console.log('Added the Edit Staff modal.');
} else {
  console.log('Edit modal already present, skipping that part.');
}

// ---- 2. Add the Edit button to the profile modal, right after Message ----
const msgBtnIdx = content.indexOf('id="messageProfileBtn"');
if (!content.includes('id="editProfileBtn"') && msgBtnIdx !== -1) {
  const closeBtnIdx = content.indexOf('</button>', msgBtnIdx) + '</button>'.length;
  const editBtnHtml = `
      <button class="btn btn-ghost" id="editProfileBtn" style="display:none; margin-top:10px; align-items:center; justify-content:center; gap:8px; width:auto; padding:10px 24px;">
        <i class="ti ti-edit"></i> Edit
      </button>`;
  content = content.slice(0, closeBtnIdx) + editBtnHtml + content.slice(closeBtnIdx);
  changed = true;
  console.log('Added Edit button to the profile modal.');
} else if (content.includes('id="editProfileBtn"')) {
  console.log('Edit button already present, skipping that part.');
}

// ---- 3. Show the Edit button for admins in openProfile(), and wire it ----
const wireAnchor = "actionBtn.style.display = isAdmin ? 'inline-flex' : 'none';";
if (content.includes(wireAnchor) && !content.includes("editProfileBtn').style.display")) {
  const wireCode = `${wireAnchor}
      document.getElementById('editProfileBtn').style.display = isAdmin ? 'inline-flex' : 'none';
      document.getElementById('editProfileBtn').onclick = () => openEditStaff(person.id);`;
  content = content.replace(wireAnchor, wireCode);
  changed = true;
  console.log('Wired Edit button visibility and click handler.');
} else if (content.includes("editProfileBtn').style.display")) {
  console.log('Edit button wiring already present, skipping that part.');
} else {
  console.log('WARNING: could not find the wire anchor. Edit button will show but may not be visibility-toggled correctly -- paste back your current directory.html if this persists.');
}

// ---- 4. Add the actual openEditStaff/save logic ----
if (!content.includes('async function openEditStaff')) {
  const fnCode = `
    async function openEditStaff(id) {
      const alertEl = document.getElementById('editStaffAlert');
      hideAlert(alertEl);
      try {
        const [staffResult, deptResult] = await Promise.all([
          apiRequest('/admin/staff/' + id),
          apiRequest('/admin/departments')
        ]);
        const s = staffResult.staff;

        document.getElementById('editDepartmentId').innerHTML =
          '<option value="">None</option>' +
          deptResult.departments.map(d => '<option value="' + d.id + '">' + d.name + '</option>').join('');

        document.getElementById('editFullName').value = s.full_name || '';
        document.getElementById('editRole').value = s.role || 'staff';
        document.getElementById('editDepartmentId').value = s.department_id || '';
        document.getElementById('editPhone').value = s.phone || '';
        document.getElementById('editBranch').value = s.branch || '';

        document.getElementById('editStaffSaveBtn').onclick = () => saveEditStaff(id);
        document.getElementById('editStaffModalBackdrop').classList.add('visible');
      } catch (err) {
        alert('Could not load this staff member\\'s details: ' + err.message);
      }
    }

    async function saveEditStaff(id) {
      const alertEl = document.getElementById('editStaffAlert');
      hideAlert(alertEl);
      const btn = document.getElementById('editStaffSaveBtn');
      btn.disabled = true;

      try {
        await apiRequest('/admin/staff/' + id, {
          method: 'PUT',
          body: {
            fullName: document.getElementById('editFullName').value.trim(),
            role: document.getElementById('editRole').value,
            departmentId: document.getElementById('editDepartmentId').value || null,
            phone: document.getElementById('editPhone').value.trim(),
            branch: document.getElementById('editBranch').value.trim()
          }
        });
        document.getElementById('editStaffModalBackdrop').classList.remove('visible');
        closeProfileModal();
        loadDirectory(document.getElementById('dirSearch').value.trim());
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
      }
    }

    document.getElementById('editStaffCancelBtn').addEventListener('click', () => {
      document.getElementById('editStaffModalBackdrop').classList.remove('visible');
    });

    `;
  content = content.replace('function closeProfileModal()', fnCode + 'function closeProfileModal()');
  changed = true;
  console.log('Added openEditStaff() and saveEditStaff() functions.');
} else {
  console.log('Edit functions already present, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndirectory.html patched successfully.');
}

