# D2 Security Fix — Handoff (2026-07-10)

Get the Supabase secrets out of the clients and gate data access behind Supabase Auth + RLS. Web is **done & verified in Cowork**; iOS/widget is **speced below for Claude Code** (needs Xcode to build/test). Supabase dashboard steps are in `SECURITY_D2_RUNBOOK.md` — Noah runs those.

**Priority reminder:** the current anon keys and `user_key`s are in git history → treat as burned → rotation (runbook Step 5) is mandatory.

---

## Part A — Web (DONE this session)

Files changed: `index.html`, `sw.js`, `.gitignore`; new: `config.js` (gitignored), `config.example.js`.

- Secrets moved out of `index.html` into `window.NUDGE_CONFIG` (untracked `config.js`, loaded via `<script src="config.js">` in `<head>`). `config.example.js` is the committed template.
- Removed both `user_key`s from client code entirely.
- Added a magic-link auth layer: `sendMagicLink()`, `captureAuthRedirect()` (reads tokens from the redirect URL hash and strips them from the URL bar), `refreshSession()`, `ensureSession()`, `bearer()` (user token when signed in, else anon), `signOut()`. Session persisted in `localStorage` key `nudge.auth.v1`.
- `cloudPush`/`cloudPull` now: return early (local-only) when not signed in — **never wipe local data**; use the user session token; upsert on `user_id` (`?on_conflict=user_id`) instead of sending a row key; retry once on 401 after refresh.
- `financeAuto()` gated on `authed()` and no longer sends a row key (finance is a separate project — see runbook 3b).
- Settings → Cloud sync row now shows Sign in / Sign out and the signed-in email.
- `sw.js`: cache bumped `nudge-v1`→`nudge-v2`; `config.js` served **network-first** so rotated keys always land fresh (never stale-cached).

Verified: `node --check` clean on all JS; auth-logic harness passed (bearer selection, 60s-pre-expiry refresh trigger, redirect-hash parse, no-false-capture).

---

## Part B — iOS + Widget (FOR CLAUDE CODE — build in Xcode)

Goal: mirror the web. No secrets in Swift source except the anon key (which becomes safe once RLS is on). **Session/refresh tokens live in the Keychain, shared with the widget via an access group — never UserDefaults.**

### B0. Move the anon key out of source (parameterize)
`NudgeStore.swift` (lines ~29–32) and `WidgetData.swift` (lines ~26–29) hardcode `baseURL`, `anon`, `userKey`.
- **Delete `userKey` entirely** from both files and from `struct Payload` (`NudgeStore.swift` line ~183/222 — drop the `user_key` field).
- Keep `baseURL` and `anon` but load them from a non-committed source. Options (pick one, tell Noah):
  - a `Secrets.xcconfig` (gitignored) exposing `SUPABASE_ANON` via Info.plist, read at runtime; ship `Secrets.example.xcconfig`. Cleanest.
  - or a gitignored `Secrets.swift` with a `Secrets.example.swift` template.
- Add the chosen ignore pattern to `.gitignore`.

### B1. Keychain session store (shared access group)
Create `AuthStore.swift` in the app target, membership also in the widget target (or a shared framework):
- Add a Keychain **access group** (e.g. `$(AppIdentifierPrefix)uk.flouty.nudge.shared`) to BOTH app and widget entitlements.
- `AuthStore` stores/reads a `Session { accessToken, refreshToken, expiresAt, email }` as JSON in a `kSecClassGenericPassword` item with `kSecAttrAccessGroup` = that group and `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` (so the widget can read it).
- API: `AuthStore.load() -> Session?`, `AuthStore.save(Session)`, `AuthStore.clear()`, `AuthStore.isAuthed`.

### B2. Auth calls (mirror web)
In the app (a small `Auth.swift` or on `NudgeStore`):
- `sendMagicLink(email:)` → `POST {base}/auth/v1/otp` with `apikey: anon`, body `{ email, create_user:true, options:{ email_redirect_to: "<your deep link>" } }`. iOS magic-link needs a Universal Link / custom URL scheme that returns to the app; handle the returned tokens in `onOpenURL` and `AuthStore.save`. If Universal Links are too much right now, a fallback is Supabase's email OTP **code** flow (`/auth/v1/verify` with a 6-digit token the user types) — simpler, no deep-link setup. Recommend the OTP-code flow for v1.
- `refreshSession()` → `POST {base}/auth/v1/token?grant_type=refresh_token`, body `{ refresh_token }`, `apikey: anon`. On 400/401 → `AuthStore.clear()`.
- `ensureSession()` → refresh if within 60s of `expiresAt`.
- `bearer()` → `AuthStore.load()?.accessToken ?? anon`.

### B3. Rewrite `refresh()` and `push()` (NudgeStore.swift)
- **Guard both on `AuthStore.isAuthed`.** If not signed in → `setSync("Local")` and RETURN. Do NOT fetch, do NOT push, do NOT let an empty result touch local state. This also removes any path where an unauthenticated/empty fetch could feed the delete logic.
- `refresh()`: drop `?user_key=eq...`; call `{base}/rest/v1/nudge_data?select=data` with `Authorization: Bearer <bearer()>`. On 401 → `refreshSession()` once, retry; else `setSync("Offline")`. Keep the existing `hasPendingPush` / `sameReminders` / `backupSnapshot("cloud")` guards exactly as they are.
- `push()`: URL `{base}/rest/v1/nudge_data?on_conflict=user_id`; body drops `user_key` (server sets `user_id = auth.uid()`); `Authorization: Bearer <bearer()>`. On 401 → refresh once, retry.

### B4. Widget (WidgetData.swift)
- Drop `userKey`. Read the session via `AuthStore.load()` from the shared Keychain group.
- If no session → return the cached/last-known data (widget must degrade gracefully, never blank-wipe). If session present → `select=data` with the bearer token; on 401 the widget can just show cached data (don't attempt refresh from the extension unless trivial).

### B5. Sign-in UI
Add a Sign in / Sign out control to `SyncSettingsView.swift` (it already has the API-key `SecureField`; add an email field + "Send code" + code entry for the OTP flow, and a signed-in/out status line).

### ⚠️ Interaction with pending Swift bugs S1/S2
S2 (transient-empty-fetch mass-delete) partly overlaps here: gating `refresh()` on `isAuthed` closes the *unauthenticated* empty-fetch path, but the **authenticated** empty-fetch path (iCloud/EK hiccup) in `RemindersSync.swift` is separate and still needs the S2 guard. Do NOT consider S2 fixed by this change. Keep them as distinct fixes.

---

## Part C — Verify (before commit is fine; before key rotation is mandatory)
- Web: `node --check` (done). Manual: sign in, sync, reload persists, sign out keeps local data.
- iOS: build in Xcode; sign in via OTP code; confirm sync; confirm widget still shows data; confirm signed-out app is local-only and never wipes.
- RLS negative test (runbook Step 4.5): anon-key-only REST read returns `[]`.

---

## Part D — Claude Code prompt (commit + push)
Use the prompt in `D2_CLAUDE_CODE_PROMPT.md`. It does NOT commit `config.js` (gitignored). It ends by clearing any stale git locks.
