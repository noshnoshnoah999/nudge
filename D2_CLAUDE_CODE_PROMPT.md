# Claude Code prompt — commit & push D2 web changes

Paste the block below into Claude Code (run from the `nudge` repo root).

**Safety notes before you run this:**
- `config.js` holds live secrets and is gitignored. It must **never** be committed. The prompt verifies this.
- Do NOT paste any keys into chat. Everything needed is already in local files.
- This commits the WEB portion only. The iOS/widget Swift work (Part B of `D2_HANDOFF.md`) is a separate task you'll do in Xcode afterward.

---

```
Commit and push the D2 security web changes in this repo. Before committing, VERIFY SAFETY:

1. Run `git check-ignore config.js` — it MUST print `config.js`. If it does NOT, STOP and tell me: config.js is not ignored and must not be committed.
2. Run `git status --short` and confirm `config.js` is NOT listed as staged or tracked. If it appears, STOP.
3. Run `grep -cE "2631e558|f7e2a914|userKey" index.html` — it MUST print `0`. If not, STOP: old row secrets are still in index.html.

If all three checks pass, stage and commit exactly these files:
- index.html
- sw.js
- .gitignore
- config.example.js
- D2_HANDOFF.md
- SECURITY_D2_RUNBOOK.md
- D2_CLAUDE_CODE_PROMPT.md

Do NOT stage config.js (it is gitignored and contains secrets).

Commit message:
"D2 security: move Supabase secrets to untracked config.js; add magic-link Auth + RLS-ready sync (web)

- Remove hardcoded anon keys + user_key row secrets from index.html
- Load config from window.NUDGE_CONFIG (config.js, gitignored; config.example.js template)
- Add magic-link auth: session token used for cloud read/write, upsert on user_id (no row key)
- cloudPush/cloudPull fail safe to local-only when signed out (never wipe local data)
- financeAuto gated on auth; sw.js cache v2 + config.js network-first
- iOS/widget spec + Supabase RLS runbook included for follow-up

NOTE: current anon keys are in git history and must be rotated after RLS lands (see SECURITY_D2_RUNBOOK.md)."

Then push to origin. After pushing, remove any stale git lock files so the next session is clean:
- `rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true`

Report the commit hash and confirm config.js was not included in the commit (run `git show --stat HEAD | grep -c config.js` — expect 0, ignoring config.example.js).
```
