// Sized to match REAL observed behavior: your pages fire 6-8 simultaneous
// requests on load (dashboard-check, notifications, unread-count, active,
// summary-today, pending, pending-staff...). Keeping only 1 connection
// warm meant just the FIRST of those got the fast path; the other 5-7
// each still paid full connection-setup cost. This keeps enough ready
// for a realistic burst, not just one at a time.
const { Pool } = require('pg');
module.exports = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  min: 8,
  max: 10,
  idleTimeoutMillis: 1800000
});
