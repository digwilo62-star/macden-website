// permanent-fix.js
//
// One complete pass covering everything found tonight:
//   1. /login in auth.js -- respond immediately, background update can't crash the server
//   2. /login-mfa in auth.js -- same fix
//   3. admin.js audit logging -- adds .catch() for genuine network failures,
//      on top of its existing error-field check
//   4. server.js -- a global safety net so ANY future unhandled rejection
//      anywhere in the app logs clearly instead of crashing the whole server
//
// Safe to run once. Each fix only applies if it finds its exact expected
// text -- if anything doesn't match, it stops and tells you exactly what,
// rather than guessing or leaving things half-changed.

const fs = require('fs');
let appliedCount = 0;
let skippedCount = 0;

function applyFix(label, filePath, oldBlock, newBlock) {
  let content = fs.readFileSync(filePath, 'utf8');
  if (content.includes(newBlock)) {
    console.log('SKIP  ' + label + ' (already applied)');
    skippedCount++;
    return;
  }
  if (!content.includes(oldBlock)) {
    console.error('FAIL  ' + label + ' -- exact text not found. Nothing changed for this one.');
    console.error('       Send Claude the current content of ' + filePath + ' around this area.');
    return;
  }
  content = content.replace(oldBlock, newBlock);
  fs.writeFileSync(filePath, content);
  console.log('OK    ' + label);
  appliedCount++;
}

// ---- Fix 1: /login ----
applyFix(
  '/login in auth.js',
  'server/routes/auth.js',
  `      supabase
        .from('staff')
        .update({ last_seen: new Date().toISOString() })
        .eq('id', staffMember.id)
        .then(() => {
          res.json({ success: true, staff: req.session.staff });
        });
    });
  } catch (err) {
    console.error('Login unexpected error:', err);`,
  `      // Respond right away -- the session is set, login is genuinely
      // complete. Updating last_seen is non-essential; the user should
      // not have to wait for it. This previously had no .catch() at all
      // -- a failure here became an unhandled rejection that crashed the
      // entire server. It now fails safely in the background instead.
      res.json({ success: true, staff: req.session.staff });
      supabase
        .from('staff')
        .update({ last_seen: new Date().toISOString() })
        .eq('id', staffMember.id)
        .then(() => {})
        .catch((err) => {
          console.error('last_seen update failed (non-fatal):', err.message);
        });
    });
  } catch (err) {
    console.error('Login unexpected error:', err);`
);

// ---- Fix 2: /login-mfa ----
applyFix(
  '/login-mfa in auth.js',
  'server/routes/auth.js',
  `      supabase
        .from('staff')
        .update({ last_seen: new Date().toISOString() })
        .eq('id', staffMember.id)
        .then(() => {
          res.json({ success: true, staff: req.session.staff });
        });
    });
  } catch (err) {
    console.error('Login MFA unexpected error:', err);`,
  `      // Same fix as /login: respond immediately, don't make the user
      // wait on a non-essential update, and never let it crash the
      // server if it fails.
      res.json({ success: true, staff: req.session.staff });
      supabase
        .from('staff')
        .update({ last_seen: new Date().toISOString() })
        .eq('id', staffMember.id)
        .then(() => {})
        .catch((err) => {
          console.error('last_seen update failed (non-fatal):', err.message);
        });
    });
  } catch (err) {
    console.error('Login MFA unexpected error:', err);`
);

// ---- Fix 3: admin.js audit log ----
applyFix(
  'audit log in admin.js',
  'server/routes/admin.js',
  `    .then(({ error }) => {
      if (error) console.error('Audit log insert failed:', error);
    });
}`,
  `    .then(({ error }) => {
      if (error) console.error('Audit log insert failed:', error);
    })
    .catch((err) => {
      // Covers genuine network-level failures, on top of the error-field
      // check above -- same "never let this crash the server" principle.
      console.error('Audit log insert failed (network):', err.message);
    });
}`
);

// ---- Fix 4: global safety net ----
{
  const filePath = 'server/server.js';
  let content = fs.readFileSync(filePath, 'utf8');
  const marker = "// TEMPORARY diagnostic: logs every single request that reaches this";
  if (content.includes('unhandledRejection')) {
    console.log('SKIP  global safety net in server.js (already applied)');
    skippedCount++;
  } else if (!content.includes(marker)) {
    console.error('FAIL  global safety net -- expected anchor not found in server.js.');
  } else {
    const safetyNet = `// Last-resort safety net: an unhandled promise rejection anywhere in the
// app (a forgotten .catch(), a background update that fails) used to
// crash the ENTIRE server for every single user. This logs it clearly
// instead, so one bad request can never take the whole site down again.
// It does not fix the underlying bug -- it just stops it from being
// catastrophic while each one gets found and fixed properly.
process.on('unhandledRejection', (reason) => {
  console.error('[UNHANDLED REJECTION - server stayed up]', reason);
});

` + marker;
    content = content.replace(marker, safetyNet);
    fs.writeFileSync(filePath, content);
    console.log('OK    global safety net in server.js');
    appliedCount++;
  }
}

console.log('');
console.log('=================================================================');
console.log(appliedCount + ' fix(es) applied, ' + skippedCount + ' already in place.');
console.log('Now run: node -c server/routes/auth.js && node -c server/routes/admin.js && node -c server/server.js');
console.log('If all three print nothing (success), you are good to push.');
console.log('=================================================================');
