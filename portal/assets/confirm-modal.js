// Shared, promise-based confirm dialog -- replaces native browser confirm()
// popups everywhere with a styled modal matching the rest of the portal.
// Self-contained (injects its own styles), so it doesn't depend on any
// other stylesheet being loaded on the page.
//
// Usage:  if (!(await confirmModal('Delete this?'))) return;

function confirmModal(message, options = {}) {
  return new Promise((resolve) => {
    const title = options.title || 'Are you sure?';
    const confirmLabel = options.confirmLabel || 'Confirm';
    const danger = options.danger !== false; // red confirm button by default

    const backdrop = document.createElement('div');
    backdrop.style.cssText = 'position:fixed; inset:0; background:rgba(0,0,0,0.45); display:flex; align-items:center; justify-content:center; z-index:9999;';

    const modal = document.createElement('div');
    modal.style.cssText = 'width:340px; background:#fff; border-radius:14px; padding:22px; font-family:-apple-system,sans-serif; box-shadow:0 10px 30px rgba(0,0,0,0.2);';

    const titleEl = document.createElement('h3');
    titleEl.textContent = title;
    titleEl.style.cssText = 'margin:0 0 10px; font-size:15px; color:#1a1a1a;';

    const msgEl = document.createElement('p');
    msgEl.textContent = message;
    msgEl.style.cssText = 'margin:0 0 20px; font-size:13px; color:#555; line-height:1.5;';

    const actions = document.createElement('div');
    actions.style.cssText = 'display:flex; gap:8px; justify-content:flex-end;';

    const cancelBtn = document.createElement('button');
    cancelBtn.textContent = 'Cancel';
    cancelBtn.style.cssText = 'padding:8px 16px; border-radius:8px; border:1px solid #ddd; background:#fff; cursor:pointer; font-size:13px;';

    const confirmBtn = document.createElement('button');
    confirmBtn.textContent = confirmLabel;
    confirmBtn.style.cssText = 'padding:8px 16px; border-radius:8px; border:none; cursor:pointer; font-size:13px; font-weight:600; color:#fff; background:' + (danger ? '#dc2626' : '#0d5c2f') + ';';

    function close(result) {
      document.body.removeChild(backdrop);
      resolve(result);
    }

    cancelBtn.onclick = () => close(false);
    confirmBtn.onclick = () => close(true);
    backdrop.onclick = (e) => { if (e.target === backdrop) close(false); };

    actions.appendChild(cancelBtn);
    actions.appendChild(confirmBtn);
    modal.appendChild(titleEl);
    modal.appendChild(msgEl);
    modal.appendChild(actions);
    backdrop.appendChild(modal);
    document.body.appendChild(backdrop);

    confirmBtn.focus();
  });
}

