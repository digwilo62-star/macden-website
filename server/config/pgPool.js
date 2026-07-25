const { Pool } = require('pg');

// Shared Postgres connection pool -- used by the session store (server.js)
// and anywhere else that needs a direct query against the sessions table,
// like "log out of all devices" in settings.js.
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false } // required for Supabase's connection pooler
});

module.exports = pgPool;

