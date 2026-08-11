#!/bin/bash
# fix-settings-idcard-button.sh
#
# Adds a "Staff ID Card" panel to portal/settings.html, matching the
# existing .set-panel style used by Profile/Notifications/Security, plus
# the JS to request a card and check status. Anchored on two exact lines
# confirmed from your real settings.html -- safe to re-run.

set -e

if grep -q "idCardStatusText" portal/settings.html; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

if ! grep -qF "<!-- Notifications -->" portal/settings.html; then
  echo "ERROR: could not find the expected anchor '<!-- Notifications -->' in portal/settings.html."
  echo "Nothing was changed."
  exit 1
fi

if ! grep -qF "</body>" portal/settings.html; then
  echo "ERROR: could not find </body> in portal/settings.html."
  echo "Nothing was changed."
  exit 1
fi

cat > .tmp-settings-panel.html << 'PANEL_EOF'

        <!-- Staff ID Card -->
        <div class="set-panel">
          <h2>Staff ID Card</h2>
          <p class="sub">Request a printable MACDEN staff ID card using your profile photo.</p>
          <div id="idCardStatusText" style="font-size:13px; color:var(--text-secondary); margin-bottom:14px;">Checking your request status…</div>
          <button class="btn btn-primary" id="idCardRequestBtn" style="width:auto; padding:9px 20px; display:none;">Request ID Card</button>
          <a class="btn btn-primary" id="idCardViewLink" href="#" target="_blank" style="width:auto; padding:9px 20px; display:none; text-decoration:none; align-items:center; justify-content:center;">View / Print My ID Card</a>
        </div>

PANEL_EOF

cat > .tmp-settings-script.html << 'SCRIPT_EOF'
  <script>
  (function(){
    const statusText = document.getElementById('idCardStatusText');
    const requestBtn = document.getElementById('idCardRequestBtn');
    const viewLink = document.getElementById('idCardViewLink');

    function refreshIdCardStatus(){
      fetch('/api/id-card/request/status', { credentials: 'include' })
        .then(r => r.json())
        .then(({ request }) => {
          if (!request) {
            statusText.textContent = "You haven't requested a staff ID card yet.";
            requestBtn.style.display = 'inline-flex';
            viewLink.style.display = 'none';
            return;
          }
          if (request.status === 'pending') {
            statusText.textContent = 'Your ID card request is pending admin approval.';
            requestBtn.style.display = 'none';
            viewLink.style.display = 'none';
          } else if (request.status === 'approved') {
            statusText.textContent = 'Your ID card has been approved.';
            requestBtn.style.display = 'none';
            viewLink.style.display = 'inline-flex';
            viewLink.href = 'id-card-view.html?requestId=' + request.id;
          } else if (request.status === 'rejected') {
            statusText.textContent = 'Your last request was not approved.' + (request.rejection_reason ? ' Reason: ' + request.rejection_reason : '');
            requestBtn.style.display = 'inline-flex';
            viewLink.style.display = 'none';
          }
        })
        .catch(() => { statusText.textContent = 'Could not check ID card status right now.'; });
    }

    requestBtn.addEventListener('click', function(){
      requestBtn.disabled = true;
      fetch('/api/id-card/request', { method: 'POST', credentials: 'include' })
        .then(r => r.json().then(data => ({ ok: r.ok, data })))
        .then(({ ok, data }) => {
          requestBtn.disabled = false;
          if (!ok) { alert(data.error || 'Could not submit request.'); return; }
          refreshIdCardStatus();
        })
        .catch(() => { requestBtn.disabled = false; alert('Something went wrong submitting your request.'); });
    });

    refreshIdCardStatus();
  })();
  </script>
SCRIPT_EOF

cat > .tmp-patch-settings.js << 'NODE_EOF'
const fs = require('fs');

const filePath = 'portal/settings.html';
let content = fs.readFileSync(filePath, 'utf8');

const panel = fs.readFileSync('.tmp-settings-panel.html', 'utf8');
const script = fs.readFileSync('.tmp-settings-script.html', 'utf8');

content = content.replace('<!-- Notifications -->', panel + '\n        <!-- Notifications -->');
content = content.replace('</body>', script + '</body>');

fs.writeFileSync(filePath, content);
console.log('    Inserted ID Card panel before Notifications, and script before </body>.');
NODE_EOF

echo "==> Patching portal/settings.html"
node .tmp-patch-settings.js
rm .tmp-patch-settings.js .tmp-settings-panel.html .tmp-settings-script.html

echo ""
echo "Done. Push with your usual save-progress.sh."
