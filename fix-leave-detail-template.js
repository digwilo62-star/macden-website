// Adds a detail "template" view for reviewing a leave request -- clicking
// any pending request row opens a clean, formatted document-style view
// (staff name, department, dates, days, reason) instead of just the
// compact table row, with Approve/Reject right there too.
//
//   node fix-leave-detail-template.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'portal', 'leave.html');
let content = fs.readFileSync(filePath, 'utf8');
content = content.replace(/\r\n/g, '\n');
let changed = false;

// ---- 1. Add the detail modal HTML ----
const detailModalHtml = `
  <div class="modal-backdrop" id="leaveDetailBackdrop">
    <div class="modal" style="width: 440px;">
      <div style="text-align:center; padding-bottom:16px; border-bottom:1px solid var(--border); margin-bottom:16px;">
        <h3 style="margin-bottom:2px;">Leave Request</h3>
        <p style="font-size:11.5px; color:var(--text-muted);">MACDEN Portal — Official Record</p>
      </div>
      <div class="review-row" style="display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--border); font-size:13px;">
        <span style="color:var(--text-secondary);">Staff Member</span><strong id="ldStaffName">—</strong>
      </div>
      <div class="review-row" style="display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--border); font-size:13px;">
        <span style="color:var(--text-secondary);">Leave Type</span><strong id="ldType">—</strong>
      </div>
      <div class="review-row" style="display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--border); font-size:13px;">
        <span style="color:var(--text-secondary);">Start Date</span><strong id="ldStart">—</strong>
      </div>
      <div class="review-row" style="display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--border); font-size:13px;">
        <span style="color:var(--text-secondary);">End Date</span><strong id="ldEnd">—</strong>
      </div>
      <div class="review-row" style="display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--border); font-size:13px;">
        <span style="color:var(--text-secondary);">Total Days</span><strong id="ldDays">—</strong>
      </div>
      <div style="padding:12px 0;">
        <div style="color:var(--text-secondary); font-size:13px; margin-bottom:6px;">Reason</div>
        <div id="ldReason" style="font-size:13px; background:var(--surface-raised); border-radius:var(--radius-sm); padding:10px 12px; min-height:40px;">—</div>
      </div>
      <div class="modal-actions" id="leaveDetailActions">
        <button class="btn btn-ghost" id="leaveDetailCloseBtn">Close</button>
      </div>
    </div>
  </div>
`;

if (!content.includes('id="leaveDetailBackdrop"')) {
  content = content.replace('<script src="assets/api.js"></script>', detailModalHtml + '\n  <script src="assets/api.js"></script>');
  changed = true;
  console.log('Added the Leave Request detail template modal.');
} else {
  console.log('Detail modal already present, skipping that part.');
}

// ---- 2. Make pending rows clickable, opening the detail view ----
const oldRowStart = "'<div class=\"lv-row\" style=\"grid-template-columns: minmax(120px, 160px) minmax(80px, 100px) minmax(80px, 100px) minmax(80px, 100px) minmax(120px, 1fr) minmax(130px, 160px);\">' +";
const newRowStart = "'<div class=\"lv-row\" style=\"grid-template-columns: minmax(120px, 160px) minmax(80px, 100px) minmax(80px, 100px) minmax(80px, 100px) minmax(120px, 1fr) minmax(130px, 160px); cursor:pointer;\" onclick=\"openLeaveDetail(\\'' + r.id + '\\')\">' +";

if (content.includes(oldRowStart)) {
  content = content.replace(oldRowStart, newRowStart);
  changed = true;
  console.log('Made pending rows clickable to open the detail view.');
} else if (content.includes('openLeaveDetail(')) {
  console.log('Rows already clickable, skipping that part.');
} else {
  console.log('WARNING: could not find the expected row-rendering line (may be due to different column widths from an earlier fix). Nothing changed for that part -- paste back your current leave.html if this persists.');
}

// ---- 2b. Stop the inline Approve/Reject buttons from ALSO triggering the
// row's new click-to-open-detail behavior (event bubbling) ----
const oldButtons = "'<div><button class=\"approve-btn\"onclick=\"reviewRequest(\\'' + r.id + '\\', \\'approve\\')\">Approve</button><button class=\"reject-btn\" onclick=\"reviewRequest(\\'' + r.id+ '\\', \\'reject\\')\">Reject</button></div>' +";
const newButtons = "'<div><button class=\"approve-btn\" onclick=\"event.stopPropagation(); reviewRequest(\\'' + r.id + '\\', \\'approve\\')\">Approve</button><button class=\"reject-btn\" onclick=\"event.stopPropagation(); reviewRequest(\\'' + r.id + '\\', \\'reject\\')\">Reject</button></div>' +";

if (content.includes(oldButtons)) {
  content = content.replace(oldButtons, newButtons);
  changed = true;
  console.log('Prevented Approve/Reject clicks from also opening the detail modal.');
} else if (content.includes('event.stopPropagation(); reviewRequest')) {
  console.log('Button click-bubbling already prevented, skipping that part.');
} else {
  console.log('NOTE: could not find the exact Approve/Reject button markup to add stopPropagation -- this is a minor UX polish, not a functional break, if it does not apply cleanly.');
}

// ---- 3. Add the openLeaveDetail function, using the already-loaded pendingRequestsCache ----
if (!content.includes('function openLeaveDetail')) {
  const fnCode = `
    let pendingRequestsCache = [];

    function openLeaveDetail(id) {
      const r = pendingRequestsCache.find(req => req.id === id);
      if (!r) return;

      document.getElementById('ldStaffName').textContent = r.staffName + (r.staffIsActive === false ? ' (Deactivated)' : '');
      document.getElementById('ldType').textContent = r.leave_type;
      document.getElementById('ldStart').textContent = new Date(r.start_date).toLocaleDateString();
      document.getElementById('ldEnd').textContent = new Date(r.end_date).toLocaleDateString();
      document.getElementById('ldDays').textContent = r.days;
      document.getElementById('ldReason').textContent = r.reason || 'No reason given.';

      document.getElementById('leaveDetailActions').innerHTML =
        '<button class="btn btn-ghost" id="leaveDetailCloseBtn">Close</button>' +
        '<button class="approve-btn" style="padding:8px 16px; font-size:12.5px;" onclick="reviewRequest(\\'' + r.id + '\\', \\'approve\\'); closeLeaveDetail();">Approve</button>' +
        '<button class="reject-btn" style="padding:8px 16px; font-size:12.5px;" onclick="reviewRequest(\\'' + r.id + '\\', \\'reject\\'); closeLeaveDetail();">Reject</button>';
      document.getElementById('leaveDetailCloseBtn').addEventListener('click', closeLeaveDetail);

      document.getElementById('leaveDetailBackdrop').classList.add('visible');
    }

    function closeLeaveDetail() {
      document.getElementById('leaveDetailBackdrop').classList.remove('visible');
    }

    `;
  content = content.replace('async function loadPending()', fnCode + 'async function loadPending()');
  changed = true;
  console.log('Added openLeaveDetail() / closeLeaveDetail() functions.');
}

// ---- 4. Cache the pending requests when they load, so the detail view can look them up ----
const oldCacheAnchor = "const result = await apiRequest('/leave/pending');";
const newCacheAnchor = "const result = await apiRequest('/leave/pending');\n        pendingRequestsCache = result.requests;";

if (content.includes(oldCacheAnchor) && !content.includes('pendingRequestsCache = result.requests;')) {
  content = content.replace(oldCacheAnchor, newCacheAnchor);
  changed = true;
  console.log('Wired pending requests to cache for the detail view.');
} else if (content.includes('pendingRequestsCache = result.requests;')) {
  console.log('Caching already wired, skipping that part.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nleave.html patched successfully.');
}

