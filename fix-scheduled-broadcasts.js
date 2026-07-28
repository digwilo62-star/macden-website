// Adds a "Send Now / Schedule for later" option to the Broadcast composer,
// and a "Scheduled" section on the sent-history list showing what's queued
// up. Wires the frontend to the #33 backend feature (built earlier, never
// had a UI). Edits accounting/broadcasts.html in place.
//
//   node fix-scheduled-broadcasts.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'broadcasts.html');
let content = fs.readFileSync(filePath, 'utf8');
let changed = false;

// ---- 1. Add the scheduling field to the compose form ----
const scheduleFieldHtml = `
                <div class="compose-field" style="flex-direction:column; align-items:flex-start;">
                  <label style="margin-bottom:8px;">When to send</label>
                  <div style="display:flex; gap:16px; margin-bottom:10px;">
                    <label style="display:flex; align-items:center; gap:6px; font-size:13px; font-weight:400; cursor:pointer;">
                      <input type="radio" name="sendTiming" value="now" id="sendTimingNow" checked> Send now
                    </label>
                    <label style="display:flex; align-items:center; gap:6px; font-size:13px; font-weight:400; cursor:pointer;">
                      <input type="radio" name="sendTiming" value="later" id="sendTimingLater"> Schedule for later
                    </label>
                  </div>
                  <input type="datetime-local" id="bcScheduledAt" style="display:none; padding:9px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); font-family:var(--font-body); font-size:13px;">
                </div>`;

const composeAnchor = '<div class="compose-body-area">';
if (content.includes(composeAnchor) && !content.includes('id="bcScheduledAt"')) {
  content = content.replace(composeAnchor, scheduleFieldHtml + '\n                ' + composeAnchor);
  changed = true;
  console.log('Added scheduling field to composer.');
} else if (content.includes('id="bcScheduledAt"')) {
  console.log('Scheduling field already present, skipping that part.');
}

// ---- 2. Wire the radio buttons to show/hide the date picker ----
const radioLogic = `
    document.getElementById('sendTimingLater').addEventListener('change', () => {
      document.getElementById('bcScheduledAt').style.display = 'block';
    });
    document.getElementById('sendTimingNow').addEventListener('change', () => {
      document.getElementById('bcScheduledAt').style.display = 'none';
    });
`;

if (!content.includes('sendTimingLater\').addEventListener')) {
  content = content.replace(
    "document.getElementById('newBroadcastBtn').addEventListener",
    radioLogic + '\n    document.getElementById(\'newBroadcastBtn\').addEventListener'
  );
  changed = true;
  console.log('Wired radio button show/hide logic.');
}

// ---- 3. Update the send handler to include scheduledAt when scheduling ----
const oldSendBody = `      try {
        await apiRequest('/messages/broadcast', {
          method: 'POST',
          body: { subject, body }
        });
        document.getElementById('bcSubject').value = '';
        document.getElementById('bcBody').value = '';
        document.getElementById('composeView').style.display = 'none';
        document.getElementById('listView').style.display = 'block';
        loadBroadcasts();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="ti ti-send"></i> Send to All';
      }`;

const newSendBody = `      const isScheduled = document.getElementById('sendTimingLater').checked;
      const scheduledAtValue = document.getElementById('bcScheduledAt').value;

      if (isScheduled && !scheduledAtValue) {
        showAlert(alertEl, 'Pick a date and time to schedule this for.');
        btn.disabled = false;
        btn.textContent = 'Send to All';
        return;
      }

      try {
        const result = await apiRequest('/messages/broadcast', {
          method: 'POST',
          body: {
            subject, body,
            scheduledAt: isScheduled ? new Date(scheduledAtValue).toISOString() : undefined
          }
        });
        document.getElementById('bcSubject').value = '';
        document.getElementById('bcBody').value = '';
        document.getElementById('sendTimingNow').checked = true;
        document.getElementById('bcScheduledAt').style.display = 'none';
        document.getElementById('bcScheduledAt').value = '';
        document.getElementById('composeView').style.display = 'none';
        document.getElementById('listView').style.display = 'block';

        if (result.scheduled) {
          alert('Scheduled to send on ' + new Date(result.scheduledAt).toLocaleString());
        }

        loadBroadcasts();
        loadScheduledBroadcasts();
      } catch (err) {
        showAlert(alertEl, err.message);
      } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="ti ti-send"></i> Send to All';
      }`;

if (content.includes(oldSendBody)) {
  content = content.replace(oldSendBody, newSendBody);
  changed = true;
  console.log('Updated send handler to support scheduling.');
} else if (content.includes('isScheduled')) {
  console.log('Send handler already updated, skipping that part.');
} else {
  console.log('WARNING: send handler markup not found in expected format — scheduling send logic NOT patched. The scheduling field will show, but submitting will not actually schedule yet. Contact for a manual fix.');
}

// ---- 4. Add the "Scheduled" section above the sent-history list ----
const scheduledSectionHtml = `
            <div id="scheduledSection" style="display:none; margin-bottom:20px;">
              <h2 style="font-size:14px; margin-bottom:10px; color:var(--text-secondary);">Scheduled — Not Yet Sent</h2>
              <div class="bc-list" id="scheduledList"></div>
            </div>
`;

const listAnchor = '<div class="bc-list" id="bcList">';
if (content.includes(listAnchor) && !content.includes('id="scheduledSection"')) {
  content = content.replace(listAnchor, scheduledSectionHtml + '\n            ' + listAnchor);
  changed = true;
  console.log('Added Scheduled section to the list view.');
} else if (content.includes('id="scheduledSection"')) {
  console.log('Scheduled section already present, skipping that part.');
}

// ---- 5. Add the loadScheduledBroadcasts function + call it from init() ----
const loadScheduledFn = `
    async function loadScheduledBroadcasts() {
      const section = document.getElementById('scheduledSection');
      const list = document.getElementById('scheduledList');
      try {
        const result = await apiRequest('/messages/broadcasts/scheduled');
        if (result.scheduled.length === 0) {
          section.style.display = 'none';
          return;
        }
        section.style.display = 'block';
        list.innerHTML = result.scheduled.map(s =>
          '<div class="bc-row" style="cursor:default;">' +
            '<div class="bc-subject">' + s.subject + '</div>' +
            '<div class="bc-date">Scheduled: ' + new Date(s.scheduledAt).toLocaleString() + '</div>' +
            '<div class="bc-count">' + s.preview + '</div>' +
            '<div></div><div></div>' +
          '</div>'
        ).join('');
      } catch (err) {
        section.style.display = 'none';
      }
    }
`;

if (!content.includes('async function loadScheduledBroadcasts')) {
  content = content.replace(
    'async function loadBroadcasts() {',
    loadScheduledFn + '\n    async function loadBroadcasts() {'
  );
  changed = true;
  console.log('Added loadScheduledBroadcasts function.');
}

if (!content.includes('loadScheduledBroadcasts();\n      loadUnreadBadge();')) {
  content = content.replace(
    'loadBroadcasts();\n      loadUnreadBadge();',
    'loadBroadcasts();\n      loadScheduledBroadcasts();\n      loadUnreadBadge();'
  );
  changed = true;
  console.log('Wired loadScheduledBroadcasts() into page init.');
}

if (changed) {
  fs.writeFileSync(filePath, content, 'utf8');
  console.log('\nbroadcasts.html patched successfully.');
} else {
  console.log('\nNo changes made — everything already up to date.');
}

