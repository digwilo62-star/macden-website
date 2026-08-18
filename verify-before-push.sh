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
      # Extract inline <script> blocks and check the last one, matching
      # the same technique used to verify these files all night
      python3 -c "
import re, sys
with open('$FILE', encoding='utf-8', errors='ignore') as f:
    html = f.read()
scripts = re.findall(r'<script>(.*?)</script>', html, re.DOTALL)
if scripts:
    with open('/tmp/verify_extract.js', 'w', encoding='utf-8') as out:
        out.write(scripts[-1])
    sys.exit(0)
sys.exit(1)
" 2>/dev/null
      if [ -f /tmp/verify_extract.js ]; then
        if node -c /tmp/verify_extract.js 2>/tmp/verify_err.log; then
          echo "OK    $FILE"
          PASS=$((PASS+1))
        else
          echo "FAIL  $FILE"
          cat /tmp/verify_err.log
          FAIL=$((FAIL+1))
        fi
        rm -f /tmp/verify_extract.js
      else
        echo "SKIP  $FILE (no inline <script> found, nothing to check)"
      fi
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
