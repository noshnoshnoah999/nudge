# Nudge — Session Handoff (2026-07-10)

Session focused on **D2 (secrets-in-client security fix)**. Web code is done; Supabase RLS is live and verified; end-to-end web sign-in is NOT yet confirmed (blocked on a Supabase email rate limit). iOS/widget migration + remaining audit bugs are spec'd for Claude Code. Read this to resume cleanly.

---

## 1. What got DONE this session

### D2 web code (index.html, sw.js, config.js) — committed & pushed
- Secrets moved out of `index.html` into `window.NUDGE_CONFIG` (config.js). Removed both `user_key` row secrets entirely.
- Added magic-link auth layer: `sendMagicLink`, `captureAuthRedirect`, `refreshSession`, `ensureSession`, `bearer()`, `signOut`. Session stored in localStorage `nudge.auth.v1`.
- `cloudPush`/`cloudPull`: fail safe to local-only when signed out (NEVER wipe local data), use the user session token, upsert on `user_id` (`?on_conflict=user_id`), retry once on 401 after refresh.
- `financeAuto` gated on auth. `sw.js` cache bumped v1→v2, config.js served network-first.
- **config.js is now COMMITTED** (un-gitignored) because the app is hosted on public GitHub Pages and Pages must serve it. This is SAFE because RLS is on and config.js holds ONLY anon-role keys (verified — both JWTs decode to "role":"anon", no user_key/service_role).
- Two commits pushed to origin/main: `a93683c` and `3303c21`.

### Supabase dashboard (Noah did these; verified)
- Auth user created: **noah@flouty.uk**, uid **5c8b57ab-2646-472d-9996-664c0758f71d**.
- `nudge_data`: added `user_id` col (default auth.uid()), backfilled to the uid (195 reminders intact), unique index on user_id, NOT NULL set.
- RLS enabled on `nudge_data` with 3 policies (select/insert/update) keyed to `auth.uid() = user_id`.
- **Found & DROPPED a bypass policy** `nudge owner only` (ALL, keyed to the burned user_key) — it would have let leaked creds keep full access. This was NOT in the original runbook; caught by inspecting pg_policies.
- **Negative test PASSED** from Noah's Mac: `curl` with anon key only → `[]` / HTTP 200. Leaked keys can no longer read data.
- `study_data` (Nudge project) and `finance_data` (finance project ipjwpkqcuztahumijici) — RLS enabled, no policies (fully locked to anon).

### Hosting
- App is live on GitHub Pages: **https://noshnoshnoah999.github.io/nudge/** (Settings→Pages: main / root, public repo). A 404 seen mid-session was stale cache/mid-deploy, resolved by hard refresh / incognito.

---

## 2. What's BLOCKED / IN PROGRESS

### D2 web sign-in — NOT yet verified end-to-end
Current app state: **signed OUT** (sidebar shows "Offline", Settings→Cloud sync shows "Sign in"). On edit it flips to offline because `cloudPush` bails when not authed — this is expected, not a bug. No `nudge_data` request is made when signed out.

**Two blockers hit:**
1. **429 rate limit** — too many magic-link sends. Supabase free tier caps this hard (~2/hour). Must WAIT ~1hr from last attempt; each click resets the clock. A scheduled reminder was set for **11:25 JST today** to retry.
2. **Magic link 404s on click** — almost certainly a redirect-URL mismatch. The app requests redirect to `location.origin+location.pathname` = exactly `https://noshnoshnoah999.github.io/nudge/` (index.html line 903).

**TO FIX BEFORE NEXT SIGN-IN ATTEMPT:** In Supabase → Authentication → URL Configuration:
- Site URL: `https://noshnoshnoah999.github.io/nudge/`
- Redirect URLs: add BOTH `https://noshnoshnoah999.github.io/nudge/` AND `https://noshnoshnoah999.github.io/nudge/**`

Then: click Sign in ONCE, wait for the NEW email (old ones are expired/dead), click newest link in the SAME Chrome. Verify: sidebar leaves "Offline", Settings shows "Signed in as...", editing a reminder shows a `nudge_data` POST → 200 in Network tab, status "Synced".

**FALLBACK if magic link still 404s after redirect fix:** switch the web app to the email OTP CODE flow (type a 6-digit code instead of clicking a link) — avoids redirect URLs entirely. This is already the recommended approach for the iOS app.

---

## 3. TODO — remaining work (priority order)

### A. Finish D2 web verification (blocked on rate limit — see section 2)

### B. iOS + widget D2 migration — Claude Code, needs Xcode
Full spec in **D2_IOS_CLAUDE_CODE_PROMPT.md**. Summary: drop `userKey` from NudgeStore.swift + WidgetData.swift; move anon/baseURL to gitignored Secrets.swift; store session in a SHARED KEYCHAIN access group (app+widget), NOT UserDefaults; gate refresh()/push() on isAuthed; use email OTP-code sign-in; add sign-in UI to SyncSettingsView.swift.

### C. S2 — data-loss bug (HIGH) — do WITH the iOS session
**RemindersSync.swift `reconcile()`**: if EventKit returns an empty list transiently (iCloud hiccup), every linked reminder is treated as Apple-deleted and removed in one pass. Same class as the `nudge_recovery/` incident. NOTE: D2's auth-gating does NOT fix this — separate fix.

**Exact fix (spec):**
- Insertion point: `reconcile()` at line 302, right after `let eks = await fetchReminders(in: cal)`. Add a guard BEFORE any delete logic:
  ```swift
  // S2 guard: a transient empty EventKit fetch must never be read as "Apple deleted everything".
  if eks.isEmpty && !links.isEmpty {
      status = .error("Apple returned no reminders — skipped to protect data")
      return
  }
  ```
- Second layer, before applying deletes (near line 411 `if !nudgeIdsToDelete.isEmpty`): if `nudgeIdsToDelete.count` exceeds a threshold (e.g. > 5 OR > 30% of `links.count`), force a backup first:
  ```swift
  if nudgeIdsToDelete.count > max(5, links.count * 3 / 10) {
      nudge.backupSnapshot("sync-massdelete", force: true)
  }
  ```
  (Check `backupSnapshot`'s signature supports a `force:` param — the line-296 `backupSnapshot("sync")` is 10-min throttled, so the mass-delete case needs a forced snapshot. If `force:` doesn't exist, add it or call an unthrottled variant.)
- Test: simulate an empty fetch (deny EventKit or empty calendar) and confirm NO reminders are deleted and status shows the protective error.

### D. S1 — recurring series death (HIGH) — Claude Code / Xcode
**RemindersSync.swift `reconcile()`**, the `eChanged && eTime > nTime` branch (~line 373, `writeToNudge(&rr, from: ek)`): when Apple completes a plain recurring reminder, nothing spawns the next occurrence (only `toggleComplete` does, which sync never calls), and `writeToEK` flattens recurrence on Apple's side — so the series silently dies. Fix: after `writeToNudge`, if `rr.completed == true`, recurrence is set (freq != "none"), and previous state was incomplete, spawn the next occurrence exactly like `toggleComplete` (full copy, new id, `nextOccurrence(after:rec:)`, insert at 0, `nudgeChanged = true`); keep the completed one as history.

### E. S3 — snooze early-alert suppression (LOW) — Xcode
**Notifications.swift `reschedule()`**: early alerts skipped whenever `parseDate(r.snoozedUntil) != nil`, but `snoozedUntil` stays set after it passes. Should skip only when the snooze is still in the FUTURE.

### F. Anon key rotation — do LAST, after iOS is migrated
SECURITY_D2_RUNBOOK.md Step 5. Rotating kills the old anon key everywhere instantly; iOS still hardcodes it, so rotate only once ALL clients are on Auth. Safe to defer — RLS already neutralized the leaked keys. When rotating: reset anon keys for BOTH projects, immediately update config.js + iOS Secrets, redeploy/rebuild.

### G. Design decisions (discuss, then do) — lower priority
- ~~**D1 (architectural):** whole-blob last-write-wins sync~~ — ✅ **FIXED 2026-07-10.** Per-item rows + tombstones; see `D1_SYNC_DESIGN_per-reminder-merge.md` §11.
- **D3:** `dismissed` never set but iOS filters on it, web doesn't — cheap web patch when a writer appears.
- **D4:** web routine tick leaves no history entry (iOS does) — "Done today" counts differ.
- **D5:** iOS hides finance/studytrack reminders, web shows them — confirm intent.
- **D6:** minor web (escape-key stale overlay state, dedupe key separator, snooze UX). NOTE: sw.js v1→v2 already done this session.

---

## 4. Key project rules to remember
- Confirm understanding before building; ask if <100% sure. Safety & security first.
- Never ask Noah to paste keys/API keys into chat. Anon USER IDs (uuid) are fine to paste; anon keys, service_role, passwords, user_key are NOT.
- Change web + iOS + macOS together — don't ship web-only.
- Cowork CANNOT commit to the Nudge .git (lock permission issue) — commits/pushes happen via Claude Code prompts. End Claude Code prompts by clearing stale git locks: `rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true`.
- Always write MD handoff files at end of long sessions (this file) and update memory.

## 5. Files created/changed this session
- Changed & pushed: `index.html`, `sw.js`, `.gitignore`, `config.js` (now committed).
- New docs (in repo root): `config.example.js`, `SECURITY_D2_RUNBOOK.md`, `D2_HANDOFF.md`, `D2_CLAUDE_CODE_PROMPT.md`, `D2_IOS_CLAUDE_CODE_PROMPT.md`, `SESSION_HANDOFF_2026-07-10.md` (this file).
- Scheduled task: `nudge-signin-retry` fires 11:25 JST 2026-07-10.
