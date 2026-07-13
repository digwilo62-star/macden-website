const { createClient } = require('@supabase/supabase-js');

// IMPORTANT: this uses the service_role key, never the anon key.
// This file only ever runs server-side — it must never be imported
// into anything that ships to the browser.
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  }
);

module.exports = supabase;

