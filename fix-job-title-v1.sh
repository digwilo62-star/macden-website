#!/bin/bash
# fix-job-title-v1.sh
#
# Adds a real, free-text "Job Title" field to Edit Staff -- separate from
# "Account Type" (which is actually the login permission level, staff/admin,
# not a job title). This is what will show as ROLE on the ID card going
# forward instead of the account permission.
#
# Patches server/routes/admin.js (GET select + PUT handler) and
# portal/directory.html (modal field, load, save). Safe to re-run.

set -e

if grep -q "editJobTitle" portal/directory.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-jobtitle.js << 'NODE_EOF'
const fs = require('fs');

function readNormalized(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const usesCRLF = raw.includes('\r\n');
  return { normalized: raw.replace(/\r\n/g, '\n'), usesCRLF };
}
function writeRestoringLineEndings(filePath, normalizedContent, usesCRLF) {
  const out = usesCRLF ? normalizedContent.replace(/\n/g, '\r\n') : normalizedContent;
  fs.writeFileSync(filePath, out);
}

// ---------- 1. server/routes/admin.js ----------
{
  const filePath = 'server/routes/admin.js';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  const oldSelect = ".select('id, full_name, role, department_id, phone, branch, staff_id')";
  const newSelect = ".select('id, full_name, role, department_id, phone, branch, staff_id, job_title')";

  if (!content.includes(oldSelect)) {
    console.error('ERROR: could not find the GET /staff/:id select line in admin.js.');
    process.exit(1);
  }
  content = content.replace(oldSelect, newSelect);

  const oldPut = `    const { fullName, role, departmentId, phone, branch, staffId } = req.body;
    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null,
        staff_id: staffId || null
      })
      .eq('id', req.params.id);`;

  const newPut = `    const { fullName, role, departmentId, phone, branch, staffId, jobTitle } = req.body;
    const { error } = await supabase
      .from('staff')
      .update({
        full_name: fullName,
        role: role,
        department_id: departmentId,
        phone: phone || null,
        branch: branch || null,
        staff_id: staffId || null,
        job_title: jobTitle || null
      })
      .eq('id', req.params.id);`;

  if (!content.includes(oldPut)) {
    console.error('ERROR: could not find the PUT /staff/:id handler block in admin.js.');
    process.exit(1);
  }
  content = content.replace(oldPut, newPut);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched server/routes/admin.js (GET select + PUT handler).');
}

// ---------- 2. portal/directory.html ----------
{
  const filePath = 'portal/directory.html';
  let { normalized: content, usesCRLF } = readNormalized(filePath);

  // Insert Job Title field right after Account Type's closing </div>
  const anchorBlock = `<label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Account Type</label>
        <select id="editRole" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
          <option value="staff">Staff</option>
          <option value="admin">Admin</option>
        </select>
      </div>`;

  const newBlock = `<label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Account Type</label>
        <select id="editRole" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
          <option value="staff">Staff</option>
          <option value="admin">Admin</option>
        </select>
      </div>
      <div style="margin-bottom:12px;">
        <label style="display:block; font-size:12.5px; font-weight:600; margin-bottom:6px;">Job Title (for ID card)</label>
        <input type="text" id="editJobTitle" placeholder="e.g. Branch Manager" style="width:100%; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); box-sizing:border-box;">
      </div>`;

  if (!content.includes(anchorBlock)) {
    console.error('ERROR: could not find the Account Type field block in directory.html.');
    process.exit(1);
  }
  content = content.replace(anchorBlock, newBlock);

  // openEditStaff(): populate the field
  const oldPopulate = `document.getElementById('editStaffId').value = s.staff_id || '';
        document.getElementById('editRole').value = s.role || 'staff';`;
  const newPopulate = `document.getElementById('editStaffId').value = s.staff_id || '';
        document.getElementById('editRole').value = s.role || 'staff';
        document.getElementById('editJobTitle').value = s.job_title || '';`;

  if (!content.includes(oldPopulate)) {
    console.error('ERROR: could not find the editStaffId/editRole populate lines in directory.html.');
    process.exit(1);
  }
  content = content.replace(oldPopulate, newPopulate);

  // saveEditStaff(): send the field
  const oldSave = `staffId: document.getElementById('editStaffId').value.trim() || null,
            role: document.getElementById('editRole').value,`;
  const newSave = `staffId: document.getElementById('editStaffId').value.trim() || null,
            role: document.getElementById('editRole').value,
            jobTitle: document.getElementById('editJobTitle').value.trim() || null,`;

  if (!content.includes(oldSave)) {
    console.error('ERROR: could not find the staffId/role save lines in directory.html.');
    process.exit(1);
  }
  content = content.replace(oldSave, newSave);

  writeRestoringLineEndings(filePath, content, usesCRLF);
  console.log('    Patched portal/directory.html (modal field, load, save).');
}
NODE_EOF

node .tmp-patch-jobtitle.js
rm .tmp-patch-jobtitle.js

echo ""
echo "Done. Push with your usual save-progress.sh."
