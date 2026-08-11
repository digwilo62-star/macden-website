#!/bin/bash
# fix-verify-server-wiring.sh
#
# Finishes what add-staff-verification.sh couldn't: wiring the verify route
# into server/server.js. The original script used python3 for this step,
# which isn't aliased in Git Bash on Windows -- this version uses node
# instead, since that's guaranteed to already be installed.

set -e

echo "==> Wiring the route into server/server.js"
if grep -q "require('./routes/verify')" server/server.js; then
  echo "    Already wired in -- skipping (safe to re-run)."
else
  if ! grep -qF "app.use('/api/accounting', requireAuth);" server/server.js; then
    echo "    ERROR: could not find the expected anchor line in server/server.js."
    echo "    Expected to find: app.use('/api/accounting', requireAuth);"
    echo "    Nothing was changed. Check server/server.js manually and re-run."
    exit 1
  fi

  cat > .tmp-patch-verify.js << 'NODE_EOF'
const fs = require('fs');
const filePath = 'server/server.js';
let content = fs.readFileSync(filePath, 'utf8');

const anchor = "app.use('/api/accounting', requireAuth);";
const insertion =
  "// --- MACDEN Staff Verification (public, no auth) ---\n" +
  "const verifyRoutes = require('./routes/verify');\n" +
  "app.use(verifyRoutes);\n" +
  "// --- end staff verification block ---\n\n";

content = content.replace(anchor, insertion + anchor);
fs.writeFileSync(filePath, content);
console.log('    Inserted require + mount before the requireAuth line.');
NODE_EOF

  node .tmp-patch-verify.js
  rm .tmp-patch-verify.js
fi

echo "==> Installing express-rate-limit"
npm install express-rate-limit --save

echo ""
echo "=================================================================="
echo "Done. Two manual steps still remain:"
echo ""
echo "1. Run server/migrations/add_verification_token.sql in the Supabase"
echo "   SQL editor -- this script doesn't touch your database."
echo ""
echo "2. Confirm the departments join in server/routes/verify.js matches"
echo "   your schema (see the NOTE comment near the top of that file)."
echo ""
echo "Then push with your usual save-progress.sh."
echo "=================================================================="
