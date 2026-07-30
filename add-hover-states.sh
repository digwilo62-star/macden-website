#!/usr/bin/env bash
# Adds hover states to buttons/rows that were missing them: Directory's
# Deactivate/Reactivate button, Documents download/delete, Policies
# read/edit/delete, Leave approve/reject, Broadcasts 'who's read this?',
# org chart node hover lift, notification/search dropdown items, and
# Directory row highlight. Appends to the shared stylesheet (loaded on
# every page) rather than replacing anything -- lower risk than the
# HTML patches, no anchor-matching needed. Kept the additions specific
# and targeted, deliberately avoided a broad catch-all rule that could
# have caused unpredictable visual side effects on buttons not directly
# checked here.
set -e
cat >> accounting/assets/portal-style.css << 'EOF_HOVER_CSS'

/* ============================================================
   Hover states — appended in a targeted pass to fix missing/weak
   hover feedback across the portal.
   ============================================================ */

/* Directory profile modal's Deactivate/Reactivate button — this one
   gets its red/green color set dynamically via inline styles in JS
   (depending on current status), so it needs its own hover rule rather
   than relying on the generic .btn-ghost hover, which would clash. */
#deactivateProfileBtn:hover {
  opacity: 0.85;
}

/* Documents: download/delete action buttons */
.doc-download-btn:hover { border-color: var(--primary); color: var(--primary); }
.doc-delete-btn:hover { color: var(--error); }

/* Policies: Read Policy button, Edit/Delete actions */
.pol-read-btn:hover { border-color: var(--primary); color: var(--primary); background: var(--primary-dim); }

/* Leave & Requests: Approve/Reject buttons */
.approve-btn:hover { background: var(--success); color: #fff; }
.reject-btn:hover { background: var(--error); color: #fff; }

/* Broadcasts: "Who's read this?" button */
.bc-row button:hover { border-color: var(--primary); color: var(--primary); }

/* Org chart nodes — subtle lift on hover to show they're informational, not dead */
.org-node { transition: box-shadow 0.15s ease, transform 0.15s ease; }
.org-node:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.08); transform: translateY(-1px); }

/* Notification dropdown items */
.notif-item:hover { background: var(--surface-raised); }

/* Search dropdown results */
.search-result-row:hover { background: var(--surface-raised); }

/* Directory rows and Manage Staff rows — subtle highlight to show clickability */
.dir-row:hover { background: var(--surface-raised); cursor: pointer; }

/* Compose recipient chip remove (x) button */
.compose-chip button:hover { opacity: 0.7; }

EOF_HOVER_CSS
echo "Hover states added. Hard-refresh (Ctrl+F5) to see them -- no server restart needed, this is CSS only."