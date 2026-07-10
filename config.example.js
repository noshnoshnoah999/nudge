/* ============================================================
   Nudge — client config (TEMPLATE)
   ------------------------------------------------------------
   Copy this file to `config.js` and fill in your values.
   `config.js` is gitignored — it must NEVER be committed.

   The anon key is SAFE to ship ONLY once Row Level Security (RLS)
   is enabled on your Supabase tables with policies keyed to
   auth.uid(). Until RLS is on, do not host this app publicly.
   The old `user_key` model is gone — data access is gated by the
   signed-in Supabase Auth session, not by a secret row key.
   ============================================================ */
window.NUDGE_CONFIG = {
  supabase: {
    url:  'https://YOUR-NUDGE-PROJECT.supabase.co',
    anon: 'YOUR_NUDGE_ANON_KEY'      // publishable anon key (safe with RLS on)
  },
  // Finance is a separate Supabase project. Leave anon empty to disable
  // finance auto-reminders. RLS must also be enabled on its table.
  finance: {
    url:  'https://YOUR-FINANCE-PROJECT.supabase.co',
    anon: ''                          // finance anon key, or '' to disable
  }
};
