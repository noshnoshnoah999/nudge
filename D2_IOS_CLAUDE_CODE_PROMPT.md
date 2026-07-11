# Claude Code prompt — iOS + widget D2 Auth migration

Paste the block below into Claude Code, run from the `nudge` repo root **with Xcode available** (this needs to build & test).

**Context for you (Noah), before running:**
- The web app is already migrated to Supabase Auth + RLS and verified. RLS is LIVE on `nudge_data` — so the iOS app and widget, which still send only the anon key, currently get `[]` back from the server (they can't read your data until this migration lands). Your data is safe in the table; iOS just can't see it until it signs in.
- Do NOT rotate the anon keys until this is done and rebuilt (see SECURITY_D2_RUNBOOK.md Step 5).
- This is Swift + Xcode work — it can't be done in Cowork.
- Auth user already exists: `noah@flouty.uk`, uid `5c8b57ab-2646-472d-9996-664c0758f71d`.

---

```
Migrate the Nudge iOS app AND its widget extension from the old Supabase "anon key + user_key row secret" model to Supabase Auth + Row Level Security, mirroring what the web app (index.html) already does. RLS is already enabled server-side (policies key on auth.uid() = user_id), so unauthenticated requests return []. Build and test in Xcode after each major step.

Read these first to match the existing patterns exactly:
- index.html — the auth layer (sendMagicLink/refreshSession/ensureSession/bearer/captureAuthRedirect) and the rewritten cloudPush/cloudPull. Mirror this behaviour in Swift.
- ios/Nudge/Nudge/NudgeStore.swift — refresh() (~line 50), push() (~line 214), persistNow() (~206), struct Payload (~183), the hardcoded baseURL/anon/userKey (~29-32).
- ios/Nudge/NudgeWidgets/WidgetData.swift — enum NudgeFeed (~line 24-42): hardcoded baseURL/anon/userKey and fetch().
- ios/Nudge/Nudge/SyncSettingsView.swift — the AI-key SecureField section (~line 79) is the UI pattern to copy for a sign-in section.

Bundle IDs: app = uk.flouty.Nudge, widget = uk.flouty.Nudge.NudgeWidgets.

STEP 0 — Get secrets out of Swift source.
- Delete the `userKey` constant from NudgeStore.swift and WidgetData.swift, and remove the `user_key` field from struct Payload.
- Keep baseURL and anon, but move them out of source into a gitignored Secrets file. Create Secrets.swift (gitignored) with `enum Secrets { static let supabaseURL = "..."; static let supabaseAnon = "..." }`, and commit a Secrets.example.swift template. Add `Secrets.swift` to .gitignore. Populate Secrets.swift with the CURRENT values so the app keeps building. Reference Secrets.supabaseURL / Secrets.supabaseAnon everywhere baseURL/anon were used.

STEP 1 — Shared Keychain for the session (app + widget).
There is currently NO App Group (WidgetData fetches independently). Add a Keychain access group shared by both targets so the widget can read the session:
- Add a Keychain Sharing capability / access group (e.g. "$(AppIdentifierPrefix)uk.flouty.Nudge.shared") to BOTH the app and widget entitlements.
- Create AuthStore.swift, added to BOTH targets (or a shared framework). It stores a Codable `Session { accessToken: String; refreshToken: String; expiresAt: Date; email: String? }` as JSON in a kSecClassGenericPassword Keychain item with kSecAttrAccessGroup = that group and kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock (so the widget can read while locked-after-first-unlock).
- API: static func load() -> Session?, static func save(_:), static func clear(), static var isAuthed: Bool. Do NOT use UserDefaults for tokens.

STEP 2 — Auth calls (app target). Create Auth.swift (or extend NudgeStore):
- Use the EMAIL OTP CODE flow (not deep-link magic links) for v1 — simpler, no Universal Link setup:
  - sendCode(email:) -> POST {url}/auth/v1/otp, header apikey: anon, body {"email": email, "create_user": true}. This emails a 6-digit code.
  - verifyCode(email:token:) -> POST {url}/auth/v1/verify, header apikey: anon, body {"type":"email","email":email,"token":token}. On success decode access_token, refresh_token, expires_in, user.email → AuthStore.save (expiresAt = now + expires_in).
- refreshSession() -> POST {url}/auth/v1/token?grant_type=refresh_token, apikey: anon, body {"refresh_token": ...}. On 400/401 → AuthStore.clear(). On success save new session.
- ensureSession() -> if within 60s of expiresAt, refreshSession(); return whether we have a live token.
- bearer() -> AuthStore.load()?.accessToken ?? Secrets.supabaseAnon.

STEP 3 — Rewrite refresh() and push() in NudgeStore.swift.
- FAIL SAFE: at the top of both, `guard AuthStore.isAuthed else { setSync("Local"); return }`. Never fetch, never push, never let an empty/unauth response touch local state when signed out. Preserve ALL existing guards (hasPendingPush, sameReminders, backupSnapshot("cloud")) exactly.
- refresh(): call await ensureSession() first; drop ?user_key=eq...; GET {url}/rest/v1/nudge_data?select=data with Authorization: Bearer bearer(). On HTTP 401 → refreshSession() once then retry once; else setSync("Offline").
- push(): call await ensureSession() first; URL {url}/rest/v1/nudge_data?on_conflict=user_id; drop user_key from the body (server sets user_id=auth.uid() via default); Authorization: Bearer bearer(); keep Prefer: resolution=merge-duplicates. On 401 → refresh once, retry once.
- Payload struct: `struct Payload: Codable { var data: NudgeData; var updated_at: String }` (no user_key).

STEP 4 — Widget (WidgetData.swift).
- NudgeFeed.fetch(): drop userKey; if let session = AuthStore.load(), GET {url}/rest/v1/nudge_data?select=data with Bearer session.accessToken; else return nil (widget shows its last cached/empty state — never crash, never blank-wipe). Do not attempt token refresh from the extension; if 401, just return nil and let the app refresh on next open.
- After the app successfully signs in or syncs, call WidgetCenter.shared.reloadAllTimelines() so the widget picks up the new session.

STEP 5 — Sign-in UI (SyncSettingsView.swift).
- Add a "Cloud sync" section modeled on the AI-key section: if signed out, show an email TextField + "Send code" button, then a code TextField + "Verify" button (calls sendCode / verifyCode). If signed in, show "Signed in as <email>" + a "Sign out" button (AuthStore.clear()). Trigger a store.refresh() after successful verify.

STEP 6 — Build & test in Xcode.
- Build both targets. Sign in with noah@flouty.uk, enter the emailed code, confirm reminders load and sync (syncState "Synced"). Confirm the widget shows data after a reload. Confirm that signed OUT, the app is local-only and never wipes the local cache. Report any build errors and fix them.

IMPORTANT — do NOT claim the S2 data-loss bug is fixed by this. Gating refresh() on isAuthed only closes the UNauthenticated empty-fetch path. The authenticated iCloud/EventKit empty-fetch mass-delete in RemindersSync.swift (S2 in BUG_AUDIT_HANDOFF.md) is a SEPARATE fix and still pending. Keep them distinct.
[UPDATE 2026-07-11: This prompt has already been executed — the D2 iOS/widget migration shipped in 42053ca. And S2 has since been fixed separately in 32f6544. This file is spent history; do not re-run it.]

When everything builds and the manual tests pass, commit with a clear message describing the Auth+Keychain migration, push to origin, and then remove any stale git locks:
`rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true`
Do NOT commit Secrets.swift (it's gitignored). Confirm with `git show --stat HEAD | grep -c Secrets.swift` → expect 0 (Secrets.example.swift is fine).
```
