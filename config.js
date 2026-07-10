/* ============================================================
   Nudge — client config (committed; served by GitHub Pages)
   ------------------------------------------------------------
   These are the project PUBLISHABLE anon keys. They are safe to
   ship publicly because Row Level Security is enabled: the anon
   key grants NOTHING without a signed-in Supabase Auth session
   (verified 2026-07-10 — anon-only REST read returns []).
   No secret row keys (user_key) or service_role keys live here.
   Rotating the anon keys is still good hygiene (they were in git
   history pre-RLS) — see SECURITY_D2_RUNBOOK.md Step 5.
   ============================================================ */
window.NUDGE_CONFIG = {
  supabase: {
    url:  'https://epaiazxcdcseijkhrncm.supabase.co',
    anon: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwYWlhenhjZGNzZWlqa2hybmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMjQ0MzQsImV4cCI6MjA5MjYwMDQzNH0.h2t_kFLZ_YPvuJlzPPiyXVbOnW4Ub_52hdaYosMoOus'
  },
  finance: {
    url:  'https://ipjwpkqcuztahumijici.supabase.co',
    anon: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlwandwa3FjdXp0YWh1bWlqaWNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMTg0NjAsImV4cCI6MjA5MjU5NDQ2MH0.aCrIwHvNLkCtA_RXPdzIybRp2EMCrBeIVS5ABCtjl48'
  }
};
