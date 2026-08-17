#!/bin/bash
# fix-announcements-inline-expand-v1.sh
#
# Replaces the "View all" link-to-another-page with an inline expand,
# right on the Dashboard. Shows 2 most recent announcements by default;
# if more exist, "View all (N)" reveals the rest in the same card --
# no navigation, no separate page, no admin/staff permission split needed
# since the underlying endpoint is already open to everyone.

set -e

if grep -q "renderAnnouncements" portal/dashboard.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-inline.js << 'NODE_EOF'
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

const filePath = 'portal/dashboard.html';
let { normalized: content, usesCRLF } = readNormalized(filePath);

// 1. Remove the "View all" link entirely from the header -- it now lives
//    as a button inside the card itself, only when there's more to show
const oldHeader = `<h2>Announcements</h2>
              <a href="broadcasts.html">View all</a>`;
const newHeader = `<h2>Announcements</h2>`;

if (!content.includes(oldHeader)) {
  console.error('ERROR: could not find the Announcements header block in dashboard.html.');
  process.exit(1);
}
content = content.replace(oldHeader, newHeader);

// 2. Replace the fetch/render block with one that supports inline expand
const oldBlock = `      try {
        const result = await apiRequest('/messages/announcements/active');
        const container = document.getElementById('announcementsContainer');
        const items = result.announcements || [];

        if (items.length === 0) {
          container.innerHTML = '<div class="empty-note">No announcements right now.</div>';
        } else {
          container.innerHTML = items.map(a => {
            const posted = new Date(a.sentAt);
            const postedStr = posted.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) +
              ' — ' + posted.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
            const snippet = (a.body || '').length > 140 ? a.body.slice(0, 140) + '…' : (a.body || '');
            return '<a href="inbox.html?id=' + a.conversationId + '" style="text-decoration:none; display:block; ' +
              'border-left:4px solid var(--primary); background:var(--primary-dim); border-radius:8px; ' +
              'padding:12px 14px; margin-bottom:10px;">' +
              '<div style="font-weight:700; font-size:13.5px; color:var(--text-primary); margin-bottom:3px;">' + a.subject + '</div>' +
              '<div style="font-size:12.5px; color:var(--text-secondary); margin-bottom:6px; line-height:1.4;">' + snippet + '</div>' +
              '<div style="font-size:10.5px; color:var(--text-muted);">Posted ' + postedStr + '</div>' +
              '</a>';
          }).join('');
        }
      } catch (err) {
        document.getElementById('announcementsContainer').innerHTML =
          '<div class="empty-note">Could not load announcements.</div>';
      }`;

const newBlock = `      try {
        const result = await apiRequest('/messages/announcements/active');
        renderAnnouncements(result.announcements || []);
      } catch (err) {
        document.getElementById('announcementsContainer').innerHTML =
          '<div class="empty-note">Could not load announcements.</div>';
      }`;

if (!content.includes(oldBlock)) {
  console.error('ERROR: could not find the announcements fetch/render block in dashboard.html.');
  process.exit(1);
}
content = content.replace(oldBlock, newBlock);

// 3. Add the renderAnnouncements() function with inline expand, right
//    before init() is called at the bottom
const initAnchor = `    init();`;
const renderFunction = `    function announcementCardHtml(a){
      const posted = new Date(a.sentAt);
      const postedStr = posted.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) +
        ' — ' + posted.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
      const snippet = (a.body || '').length > 140 ? a.body.slice(0, 140) + '…' : (a.body || '');
      return '<a href="inbox.html?id=' + a.conversationId + '" style="text-decoration:none; display:block; ' +
        'border-left:4px solid var(--primary); background:var(--primary-dim); border-radius:8px; ' +
        'padding:12px 14px; margin-bottom:10px;">' +
        '<div style="font-weight:700; font-size:13.5px; color:var(--text-primary); margin-bottom:3px;">' + a.subject + '</div>' +
        '<div style="font-size:12.5px; color:var(--text-secondary); margin-bottom:6px; line-height:1.4;">' + snippet + '</div>' +
        '<div style="font-size:10.5px; color:var(--text-muted);">Posted ' + postedStr + '</div>' +
        '</a>';
    }

    function renderAnnouncements(items){
      const container = document.getElementById('announcementsContainer');
      const VISIBLE_COUNT = 2;

      if (items.length === 0) {
        container.innerHTML = '<div class="empty-note">No announcements right now.</div>';
        return;
      }

      const visible = items.slice(0, VISIBLE_COUNT);
      const rest = items.slice(VISIBLE_COUNT);

      let html = visible.map(announcementCardHtml).join('');

      if (rest.length > 0) {
        html += '<div id="announcementsRest" style="display:none;">' + rest.map(announcementCardHtml).join('') + '</div>';
        html += '<button id="announcementsToggle" style="width:100%; padding:8px; border:1px solid var(--border); ' +
          'background:var(--surface); border-radius:8px; font-size:12.5px; font-weight:600; color:var(--primary); ' +
          'cursor:pointer; font-family:var(--font-body);">View all (' + items.length + ')</button>';
      }

      container.innerHTML = html;

      const toggleBtn = document.getElementById('announcementsToggle');
      if (toggleBtn) {
        toggleBtn.addEventListener('click', function(){
          const restEl = document.getElementById('announcementsRest');
          const expanded = restEl.style.display === 'block';
          restEl.style.display = expanded ? 'none' : 'block';
          this.textContent = expanded ? 'View all (' + items.length + ')' : 'Show less';
        });
      }
    }

    init();`;

if (!content.includes(initAnchor)) {
  console.error('ERROR: could not find the init() call in dashboard.html.');
  process.exit(1);
}
content = content.replace(initAnchor, renderFunction);

writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched portal/dashboard.html (inline expand instead of separate page).');
NODE_EOF

node .tmp-patch-inline.js
rm .tmp-patch-inline.js

echo ""
echo "Done. Push with your usual save-progress.sh."
