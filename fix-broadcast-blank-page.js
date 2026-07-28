// Fixes the blank Broadcasts page (Uncaught SyntaxError: Unexpected
// identifier 's'). Root cause: the "Who's read this?" button was built
// using a deeply nested, multiply-escaped quote string inside an inline
// onclick attribute -- extremely fragile to hand-write and easy to
// mis-transcribe. This replaces the WHOLE loadBroadcasts function with a
// version that avoids inline-onclick string escaping entirely, using a
// data-attribute + a single click listener instead. Structurally safer,
// not just a patch to the old fragile approach.
//
//   node fix-broadcast-blank-page.js

const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'accounting', 'broadcasts.html');
let content = fs.readFileSync(filePath, 'utf8');

const startMarker = 'async function loadBroadcasts() {';
const endMarker = "document.getElementById('sendTimingLater')";

const startIdx = content.indexOf(startMarker);
const endIdx = content.indexOf(endMarker);

if (startIdx === -1 || endIdx === -1 || endIdx < startIdx) {
  console.log('ERROR: Could not find the expected markers in broadcasts.html.');
  console.log('startMarker found:', startIdx !== -1, ' endMarker found:', endIdx !== -1);
  console.log('Nothing was changed. Send this output back for a manual fix.');
  process.exit(1);
}

const newLoadBroadcasts = `async function loadBroadcasts() {
      const list = document.getElementById('bcList');
      try {
        const result = await apiRequest('/messages/broadcasts');
        if (result.broadcasts.length === 0) {
          list.innerHTML = '<div class="bc-empty">No broadcasts sent yet. Click New Broadcast to send your first one.</div>';
          return;
        }
        list.innerHTML =
          '<div class="bc-row" style="font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); cursor:default;">' +
            '<div>Subject</div><div>Date Sent</div><div>Recipients</div><div>Opened</div><div></div>' +
          '</div>' +
          result.broadcasts.map(b => {
            const pct = b.recipientCount > 0 ? Math.round((b.openedCount / b.recipientCount) * 100) : 0;
            return '<div class="bc-row" data-conversation-id="' + b.id + '">' +
              '<div class="bc-subject">' + b.subject + '</div>' +
              '<div class="bc-date">' + new Date(b.sentAt).toLocaleString() + '</div>' +
              '<div class="bc-count">' + b.recipientCount + ' sent</div>' +
              '<div class="bc-opened">' + b.openedCount + ' opened (' + pct + '%)</div>' +
              '<div><button class="who-read-btn" data-conversation-id="' + b.id + '" data-subject="' + b.subject.replace(/"/g, '&quot;') + '" style="border:1px solid var(--border); border-radius:var(--radius-sm); padding:6px 12px; font-size:11.5px; font-weight:600; color:var(--text-primary); background:none; cursor:pointer; font-family:var(--font-body);">Who\\u2019s read this?</button></div>' +
              '</div>';
          }).join('');

        // Row click opens the broadcast; the "Who's read this?" button
        // stops that click from bubbling and opens the reads modal instead.
        // Using data attributes + real event listeners here instead of
        // inline onclick with escaped quotes -- much safer to generate and
        // to read.
        list.querySelectorAll('.bc-row[data-conversation-id]').forEach(row => {
          row.style.cursor = 'pointer';
          row.addEventListener('click', () => {
            window.location.href = 'inbox.html?id=' + row.dataset.conversationId;
          });
        });
        list.querySelectorAll('.who-read-btn').forEach(btn => {
          btn.addEventListener('click', (e) => {
            e.stopPropagation();
            viewReadStatus(btn.dataset.conversationId, btn.dataset.subject);
          });
        });
      } catch (err) {
        list.innerHTML = '<div class="bc-empty">' + err.message + '</div>';
      }
    }

    `;

content = content.slice(0, startIdx) + newLoadBroadcasts + content.slice(endIdx);

fs.writeFileSync(filePath, content, 'utf8');
console.log('broadcasts.html fixed -- loadBroadcasts() rewritten without fragile inline-onclick quoting.');

