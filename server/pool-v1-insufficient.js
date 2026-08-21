// The FIRST fix attempt -- only keeps 1 connection warm, insufficient
// for a page that fires many requests at once
const { Pool } = require('pg');
module.exports = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  min: 1,
  idleTimeoutMillis: 1800000
});
