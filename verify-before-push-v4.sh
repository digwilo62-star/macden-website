#!/bin/bash
# verify-before-push.sh
#
# Run this after ANY fix-*.sh script, before pushing. Checks two things
# that have caused real problems tonight:
#   1. Did anything actually change? (a script can exit "successfully"
#      without modifying anything, if an anchor didn't match and it
#      exited cleanly, or if it thought it was already applied)
#   2. Is every changed file still valid, working code? (catches syntax
#      errors before they reach the live site, not after)
#
# Safe to run as many times as you want -- it only checks, never
# modifies anything.

echo "=================================================================="
echo "STEP 1: What actually changed (uncommitted right now)"
echo "=================================================================="
CHANGED=$(git status --porcelain | awk '{print $2}' | grep -v '\.sh$')

if [ -z "$CHANGED" ]; then
  echo ""
  echo "!! NOTHING has changed since the last commit."
  echo "!! This usually means the fix script did NOT actually apply --"
  echo "!! check its output above for an 'already applied' or 'ERROR'"
  echo "!! message before assuming it worked."
  echo ""
  exit 1
fi

git status --porcelain
echo ""
git diff --stat
echo ""

echo "=================================================================="
echo "STEP 2: Syntax check on every changed file"
echo "=================================================================="
PASS=0
FAIL=0

# Extraction + syntax check both done in Node.js -- avoids depending on
# python3 being available/aliased correctly, since only node has been
# confirmed working reliably in this environment tonight.
cat > /tmp/verify_extract_and_check.js << 'NODEEOF'
const fs = require('fs');
const os = require('os');
const path = require('path');

const target = process.argv[2];
const html = fs.readFileSync(target, 'utf8');
const matches = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];

if (matches.length === 0) {
  console.log('SKIP');
  process.exit(0);
}

const lastScript = matches[matches.length - 1][1];

try {
  new Function(lastScript); // throws SyntaxError if invalid, without executing it
  console.log('OK');
} catch (err) {
  console.log('FAIL');
  console.error(err.message);
  process.exit(1);
}
NODEEOF

for FILE in $CHANGED; do
  if [ ! -f "$FILE" ]; then
    continue  # deleted file, nothing to check
  fi

  case "$FILE" in
    *.js)
      if node -c "$FILE" 2>/tmp/verify_err.log; then
        echo "OK    $FILE"
        PASS=$((PASS+1))
      else
        echo "FAIL  $FILE"
        cat /tmp/verify_err.log
        FAIL=$((FAIL+1))
      fi
      ;;
    *.html)
      RESULT=$(node /tmp/verify_extract_and_check.js "$FILE" 2>/tmp/verify_err.log)
      case "$RESULT" in
        OK*)
          echo "OK    $FILE"
          PASS=$((PASS+1))
          ;;
        SKIP*)
          echo "SKIP  $FILE (no inline <script> found, nothing to check)"
          ;;
        FAIL*)
          echo "FAIL  $FILE"
          cat /tmp/verify_err.log
          FAIL=$((FAIL+1))
          ;;
        *)
          echo "SKIP  $FILE (could not check -- $RESULT)"
          ;;
      esac
      ;;
    *)
      echo "SKIP  $FILE (not a .js or .html file)"
      ;;
  esac
done

echo ""
echo "=================================================================="
if [ "$FAIL" -eq 0 ]; then
  echo "ALL CLEAR -- $PASS file(s) passed. Safe to push."
else
  echo "STOP -- $FAIL file(s) FAILED, $PASS passed."
  echo "Do NOT push yet. Send the FAIL output above back to Claude."
fi
echo "=================================================================="

rm -f /tmp/verify_err.log
exit $FAIL
