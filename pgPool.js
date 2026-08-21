const { Pool } = require('pg');
// Shared Postgres connection pool -- used by the session store (server.js)
// and anywhere else that needs a direct query against the sessions table,
// like "log out of all devices" in settings.js.
//
// min: 1 and a long idleTimeoutMillis keep at least one connection warm
// at all times, instead of the default 10-second idle timeout tearing it
// down between requests. Confirmed via direct testing: without this, every
// click after a short pause paid the full connection-setup cost again
// (~1.4s) due to physical distance to Supabase's Ireland region. With it,
// that same follow-up request dropped to ~0ms.
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false }, // required for Supabase's connection pooler
  min: 1,
  idleTimeoutMillis: 1800000 // 30 minutes
});
module.exports = pgPool;
