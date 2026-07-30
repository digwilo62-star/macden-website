// Adds a "Pending Staff Approvals" panel to the Dashboard, admin-only.
// Uses single-line anchors (lessons learned from earlier multi-line
// matching failures caused by inconsistent whitespace in the real file).
//
//   node fix-pending-staff.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'dashboard.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- Step 1: wire loadPendingStaff() into init(), BEFORE adding any new
// functions -- doing this first avoids the new code confusing the anchor
// search for where init() actually ends. ----
const initEndAnchor = "staff.role === 'admin' ? 'Pending Approvals' : 'My Pending Leave Requests';\n      }\n    }";
if (content.includes(initEndAnchor) && !content.includes('loadPendingStaff();\n    }')) {
  content = content.replace(initEndAnchor, initEndAnchor.replace(/\n    \}$/, '\n\n      loadPendingStaff();\n    }'));
  changed = true;
  console.log('Wired loadPendingStaff() into the end of init().');
} else if (content.includes('loadPendingStaff();\n    }')) {
  console.log('Already wired into init(), skipping that part.');
} else {
  console.log('WARNING: could not find the end-of-init() anchor. The panel will still be added, but you will need to call loadPendingStaff() manually or ask for a follow-up fix.');
}

const panelHtml = `
        <div class="panel" id="pendingStaffPanel" style="display:none; margin-top:20px;">
          <div class="panel-header"><h2>Pending Staff Approvals</h2></div>
          <div id="pendingStaffList"></div>
        </div>
`;

const statGridAnchor = '<div class="stat-grid" style="grid-template-columns: repeat(2, 1fr);">';

if (content.includes(statGridAnchor) && !content.includes('id="pendingStaffPanel"')) {
  content = content.replace(statGridAnchor, panelHtml + '\n        ' + statGridAnchor);
  changed = true;
  console.log('Added Pending Staff Approvals panel.');
} else if (content.includes('id="pendingStaffPanel"')) {
  console.log('Panel already present, skipping that part.');
} else {
  console.log('WARNING: could not find the stat-grid anchor. Nothing changed.');
  process.exit(1);
}

const loadPendingFn = `
    async function loadPendingStaff() {
      try {
        const result = await apiRequest('/admin/pending-staff');
        if (result.pending.length === 0) return;

        document.getElementById('pendingStaffPanel').style.display = 'block';
        document.getElementById('pendingStaffList').innerHTML = result.pending.map(p =>
          '<div style="display:flex; justify-content:space-between; align-items:center; padding:10px 0; border-bottom:1px solid var(--border);">' +
            '<div><div style="font-size:13.5px; font-weight:600;">' + p.full_name + '</div>' +
            '<div style="font-size:12px; color:var(--text-secondary);">' + p.username + ' · ' + p.email + '</div></div>' +
            '<button class="btn btn-primary" style="width:auto; padding:7px 16px;" onclick="approveStaff(\\'' + p.id + '\\', this)">Approve</button>' +
          '</div>'
        ).join('');
      } catch (err) {
        // Fail silently -- non-admins will always hit this (403), which is expected
      }
    }

    async function approveStaff(id, btn) {
      btn.disabled = true;
      btn.textContent = 'Approving…';
      try {
        await apiRequest('/admin/approve-staff/' + id, { method: 'POST' });
        loadPendingStaff();
      } catch (err) {
        alert(err.message);
        btn.disabled = false;
        btn.textContent = 'Approve';
      }
    }

    `;

const logoutAnchor = "document.getElementById('logoutBtn').addEventListener";

if (content.includes(logoutAnchor) && !content.includes('async function loadPendingStaff')) {
  content = content.replace(logoutAnchor, loadPendingFn + logoutAnchor);
  changed = true;
  console.log('Added loadPendingStaff() and approveStaff() functions.');
} else if (content.includes('async function loadPendingStaff')) {
  console.log('Functions already present, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\ndashboard.html patched successfully.');
}

