#!/bin/bash
# fix-photo-resets-idcard-v1.sh
#
# Security: when a staff member changes their own profile photo, any
# already-approved ID card request gets reset back to pending. Their
# existing card link stops working (shows "not approved yet") until an
# admin reviews the new photo and re-approves. Doesn't touch Field Staff,
# since those photos are already admin-uploaded -- no oversight gap there.

set -e

if grep -q "ID-CARD-RESET-ON-PHOTO-ERROR" server/routes/settings.js; then
  echo "==> Already applied -- skipping (safe to re-run)."
  exit 0
fi

cat > .tmp-patch-photoreset.js << 'NODE_EOF'
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

const filePath = 'server/routes/settings.js';
let { normalized: content, usesCRLF } = readNormalized(filePath);

const anchor = `      // Update the session too, so the new photo shows up immediately on
      // every page without needing to logout and back in.
      req.session.staff.photoUrl = publicUrlData.publicUrl;`;

const insertion = `      // Security: changing your photo resets any already-approved ID card
      // back to pending, so an admin has to review and re-approve the new
      // photo before the card becomes accessible again.
      try {
        const { data: existingRequest } = await supabase
          .from('id_card_requests')
          .select('id, status')
          .eq('staff_ref_id', req.session.staff.id)
          .order('requested_at', { ascending: false })
          .limit(1)
          .maybeSingle();

        if (existingRequest && existingRequest.status === 'approved') {
          await supabase
            .from('id_card_requests')
            .update({ status: 'pending', reviewed_at: null, reviewed_by: null })
            .eq('id', existingRequest.id);
        }
      } catch (resetErr) {
        // Non-fatal -- don't fail the photo upload itself over this side effect
        console.error('[ID-CARD-RESET-ON-PHOTO-ERROR]', resetErr);
      }

`;

if (!content.includes(anchor)) {
  console.error('ERROR: could not find the expected anchor in server/routes/settings.js.');
  console.error('Nothing was changed.');
  process.exit(1);
}

content = content.replace(anchor, insertion + anchor);
writeRestoringLineEndings(filePath, content, usesCRLF);
console.log('    Patched server/routes/settings.js (photo change resets approved card to pending).');
NODE_EOF

node .tmp-patch-photoreset.js
rm .tmp-patch-photoreset.js

echo ""
echo "Done. Push with your usual save-progress.sh."
