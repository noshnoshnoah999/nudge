# Claude Code prompt — commit & push D2 web changes

Paste the block below into Claude Code (run from the `nudge` repo root).

**Why config.js is now committed:** the app is hosted on GitHub Pages (public). RLS is live on Supabase (verified 2026-07-10 — anon-only REST read returns `[]`), so the anon key is safe to expose publicly — that is its designed purpose. `config.js` holds ONLY publishable anon keys, no `user_key` or `service_role`. So it must be committed for GitHub Pages to serve it, otherwise the app shows "Local only / config.js missing".

**Safety rule that still holds:** never let a `user_key` UUID or a `service_role` key into `config.js` or `index.html`. The prompt verifies this.

---

```
Commit and push the D2 security web changes in this repo. Before committing, VERIFY SAFETY:

1. Run: grep -cE "2631e558|f7e2a914" config.js index.html
   MUST print 0 for both (no user_key row secrets anywhere). If not, STOP.
2. Confirm config.js contains only anon-role keys. For each JWT in config.js, decode the middle segment and check "role":"anon" (NOT "service_role"). If any service_role key is present, STOP.
3. Run: grep -cE "userKey|user_key" index.html
   MUST print 0. If not, STOP: old row-key logic is still in index.html.

If all checks pass, stage and commit exactly these files:
- index.html
- sw.js
- .gitignore
- config.js            (publishable anon keys only — safe with RLS on; needed by GitHub Pages)
- config.example.js
- D2_HANDOFF.md
- SECURITY_D2_RUNBOOK.md
- D2_CLAUDE_CODE_PROMPT.md
- D2_IOS_CLAUDE_CODE_PROMPT.md

Commit message:
"D2 security: Supabase Auth + RLS-ready sync (web); commit config.js (anon keys, safe with RLS)

- Remove hardcoded user_key row secrets from index.html
- Config in window.NUDGE_CONFIG via config.js (anon keys only; RLS makes them safe to serve publicly on GitHub Pages)
- Magic-link auth: user session token used for cloud read/write, upsert on user_id (no row key)
- cloudPush/cloudPull fail safe to local-only when signed out (never wipe local data)
- financeAuto gated on auth; sw.js cache v2 + config.js network-first
- RLS live on nudge_data/study_data/finance_data; anon-only read returns [] (verified)
- iOS/widget migration spec included (D2_IOS_CLAUDE_CODE_PROMPT.md)

Anon-key rotation still pending (Step 5) — do AFTER iOS is migrated so all clients cut over together."

Then push to origin. After pushing, remove any stale git lock files so the next session is clean:
- rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true

Report the commit hash.
```
