const { Pool } = require('pg');
// Shared Postgres connection pool -- used by the session store (server.js)
// and anywhere else that needs a direct query against the sessions table,
// like "log out of all devices" in settings.js.
//
// CORRECTED: an earlier fix set min:8/max:10, based on an incorrect
// assumption that every one of a page's ~8 simultaneous requests needed
// its own connection here. In reality only the session-check step uses
// this pool at all -- everything else (messages, staff, announcements)
// goes through Supabase's separate REST API, which shares the SAME total
// connection budget (15, on this project's free tier). Holding 8-10
// connections here permanently starved the rest of the app, causing the
// "Timed out acquiring connection from connection pool" errors and
// server crashes. A small pool still gets the "keep it warm" benefit
// without taking most of the project's total capacity for itself.
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }, // required for Supabase's connection pooler
  min: 2,
  max: 3,
  idleTimeoutMillis: 1800000 // 30 minutes
});
module.exports = pgPool;
