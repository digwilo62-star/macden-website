const { Pool } = require('pg');
// Shared Postgres connection pool -- used by the session store (server.js)
// and anywhere else that needs a direct query against the sessions table,
// like "log out of all devices" in settings.js.
//
// Two things confirmed via direct testing on the real database:
//   1. Session Mode (port 5432) caps at a hard 15 connections project-wide
//      -- a single page's normal request burst nearly exhausted it alone.
//      Switched to Transaction Mode (6543), built for exactly this pattern
//      of many brief, concurrent connections.
//   2. Keeping only 1 warm connection (an earlier attempt) meant just the
//      FIRST of a page's ~8 simultaneous requests got the fast path; the
//      rest still paid full connection-setup cost. min: 8 matches the
//      real number of simultaneous requests a page actually fires.
//
// Measured result: repeat page loads after a pause dropped from ~1.8-2.1s
// per request down to 2-5ms -- essentially instant.
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }, // required for Supabase's connection pooler
  min: 8,
  max: 10,
  idleTimeoutMillis: 1800000 // 30 minutes
});
module.exports = pgPool;
