const { Pool } = require('pg');
const pgPool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  min: 2,
  max: 3,
  idleTimeoutMillis: 1800000
});
module.exports = pgPool;
