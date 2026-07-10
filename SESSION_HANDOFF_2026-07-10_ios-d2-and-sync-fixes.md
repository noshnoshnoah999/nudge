# Nudge — Session Handoff (2026-07-10, Claude Code)

Supersedes `SESSION_HANDOFF_2026-07-10.md` (the earlier Cowork session) where they conflict.
That file's Supabase/dashboard details remain accurate; its TODO list is superseded by §4 here.

**Headline: the web app is retired. Nudge is iOS + Mac only now.** Three sync bugs fixed and
deployed; the iOS D2 Auth migration is written, deployed, and NOT yet signed in.

---

## 1. What shipped this session

`main` went `3303c21` → `42053ca`. Four commits, all pushed.

### S2 — sync data loss (HIGH) — `32f6544` — VERIFIED LIVE
`RemindersSync.swift reconcile()`: a transient empty EventKit fetch was read as "Apple deleted
everything" and removed every linked reminder in one pass. Same class as the `nudge_recovery/`
incident.
- Guard: `if eks.isEmpty && !links.isEmpty { throw SyncError.emptyFetch }`.
- **Deviation from the old spec:** it *throws* rather than `status = .error(...); return`. Returning
  normally let `syncNow()` fall through to `status = .ok(summary)` and stamp `lastSync` — the data
  would have been protected while the UI said "Synced".
- Second layer: forced `backupSnapshot("sync-massdelete", force: true)` when
  `nudgeIdsToDelete.count > max(5, initialLinkCount * 3 / 10)`. `initialLinkCount` is captured
  *before* loop 1, because loop 1 clears `links` as it consumes them.
- **Known trade-off:** the guard can't distinguish a failed fetch from a genuinely empty list
  (EventKit collapses both into `[]`). If you ever delete *every* reminder inside the Apple "Nudge"
  list, sync jams with the protective error. Escape hatch: delete the whole list in Apple →
  `ensureCalendar` → `freshCalendar` → links cleared.

### S1 — recurring series death (HIGH) — `32f6544` — VERIFIED LIVE
Completing a plain repeating reminder *in Apple* marked it done but never spawned the next
occurrence, because sync never calls `toggleComplete`. The series silently ended.
- Spawns the next occurrence inline in the `eChanged && eTime > nTime` branch, keeping the completed
  one as history. Gated on `!routine` (routines use `advanceRoutine`) and on the previous state
  being incomplete (so a re-sync can't duplicate).
- Insert happens *after* the in-place write at `idx` — inserting at 0 shifts that index.
- **Verified end-to-end**: made a daily test reminder, ticked it in Apple Reminders, synced.
  Original kept `completed: true` + `completedAt`; new occurrence got a new id, due +1 day,
  recurrence preserved. Apple showed the spawned copy as "Tomorrow". Cleaned up afterwards.

### S3 — snooze suppressed early alerts forever — `7523222` — BUILD-VERIFIED ONLY
`Notifications.swift reschedule()` skipped early alerts whenever `snoozedUntil` was merely *present*.
Nothing clears that field when a snooze lapses. Now checks the snooze is still pending, matching the
five other readers (`NudgeStore` 1108/1128/1167/1185, `ContentView` 674).
- **Impact is narrower than the old spec claimed.** `snooze()` moves `dueDate` for normal reminders,
  so their early alerts fall into the past and get dropped anyway. Only **routines** — which keep
  their nightly `dueDate` by design — actually lose alerts, and only until `advanceRoutine` clears
  the field overnight.
- Not runtime-verified: min snooze is 30 min, so proving it means waiting out a real snooze.

### `reinstall_nudge.sh` — Mac was installing nothing — `a71ece8` — VERIFIED
The Mac half only ran `open` on the DerivedData bundle. `/Applications/Nudge.app` — what the Dock and
Spotlight actually launch — stayed frozen at whatever build first landed there. **It was three weeks
stale (June 18) while the script printed "Mac refreshed" every run.**
- Now `ditto`s into a staging path and swaps into `/Applications`, restoring the previous bundle if
  the swap fails. `ditto` preserves the code signature (verified with `codesign --strict`).
- Also added `set -o pipefail` to the Mac `xcodebuild`: it was piped to `tail -3`, so the `if` tested
  *tail's* exit status. A failed Mac build reported success. (The iPhone half already had this fix;
  it was never applied to the Mac block.)

### D2 — iOS + widget Auth migration — `42053ca` — DEPLOYED, NOT SIGNED IN
- `userKey` deleted from `NudgeStore.swift` and `WidgetData.swift`; `user_key` removed from the
  upsert payload (server sets `user_id` from `auth.uid()`).
- URL + anon key → `ios/Nudge/Shared/Secrets.swift` (**gitignored**), with
  `Secrets.example.swift.template` committed. Named `.template` so Xcode can't compile both.
- `Shared/AuthStore.swift` — session in the Keychain under access group
  `FMF6YAVA23.uk.flouty.Nudge.shared`, `kSecAttrAccessibleAfterFirstUnlock`. Added to **both**
  targets. There is no App Group (free team), so the Keychain is the only shared store.
- `Nudge/Auth.swift` — email OTP **code** flow (`/auth/v1/otp`, `/auth/v1/verify`,
  `/auth/v1/token`), refresh, single 401 retry.
- `refresh()` / `push()` fail safe to local-only when signed out. An empty or unauthorised response
  can never reach `apply()`.
- **Bug found in passing:** `push()` never checked its HTTP status. `URLSession.data` doesn't throw
  on 4xx, so since RLS landed the app displayed **"Synced" while Supabase rejected every write**.
- Widget reads the shared session; returns `nil` rather than blanking when it can't authenticate;
  never refreshes tokens itself.
- Sign-in UI in `SyncSettingsView.swift` → Settings → **Cloud sync**.

---

## 2. Xcode gotchas discovered (these cost real time)

- **Entitlements were macOS-only.** The project had `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` and nothing
  else, so **iOS device builds shipped with no entitlements file at all**. Added
  `Nudge/NudgeiOS.entitlements` wired to `[sdk=iphoneos*]`. The calendars key stays macOS-only —
  it's a macOS sandbox key.
- **Free personal teams DO sign `keychain-access-groups`** on both the app and the `.appex`. Verified
  in the signed binaries. (They do *not* get App Groups.)
- **`Nudge/` is a `PBXFileSystemSynchronizedRootGroup`** on the app target — files dropped in that
  folder are auto-included, no pbxproj edit needed. `Shared/` and `NudgeWidgets/` are plain groups
  and need explicit `add_file_references`. The `xcodeproj` ruby gem is installed and works.
- **Debug builds put code in `Nudge.debug.dylib`**, not the main binary. `strings Nudge.app/Nudge`
  finds nothing; scan the dylib.
- `syncNow()` did **not** fire on foregrounding the Mac app during this session; had to use
  Settings → Sync now. Both call sites are in `ContentView.swift` (141, 214). Unexplained.

---

## 3. Current state

**Deployed to iPhone + Mac (both at `42053ca`, 10:39 JST).** Both apps are **signed out**, therefore
local-only: they don't fetch, don't push, don't wipe. Verified on Mac — 195 reminders in, 195 out,
no request made.

**Web app is retired.** GitHub Pages unpublished; `https://noshnoshnoah999.github.io/nudge/` returns
`404` for `/`, `config.js`, and `sw.js` (confirmed by curl). `index.html`/`config.js` still exist in
the repo — nothing deleted, so it's reversible by re-enabling Pages.
- Browsers with the PWA installed still serve it from the **service worker cache**. Unregister the
  SW + clear site data to fully remove.
- **`config.js` is still readable in the public repo**, so the anon key stays exposed until rotation.
  Harmless (RLS protects the rows; anon keys are designed to be public) but it's why rotation is
  still worth doing. After rotating, `config.js` can simply be **deleted** rather than updated.

**Sessions are per-client.** Browsers use `localStorage` (`nudge.auth.v1`); the apps use the Keychain.
Signing in one does not sign in another. Currently the only signed-in client anywhere is the
**iPhone's browser** (from a magic-link click), which is now moot since the web app is retired.

**Backup taken:** `~/Nudge_backups/manual_2026-07-10_1052/` — `nudge_cache.json` (195 reminders,
41 open / 154 completed / 29 recurring, 9 lists), `nudge_sync_links.json`, and all 60 rotating
snapshots. 4.6 MB. Same machine only — not off-site.

---

## 4. What's left

### Blocked on Noah (needs a person)
1. **Sign in on the iOS app** — Settings → Cloud sync → `noah@flouty.uk` → Send code → type the code.
   This is the whole D2 payoff and is **completely unverified**: sign-in, cloud pull, and the widget
   reading the session have never been exercised.
2. **Sign in on the Mac app** — separate Keychain, separate sign-in, separate email.
3. **Rotate the anon keys** — *last*, after 1 and 2 work. `SECURITY_D2_RUNBOOK.md` Step 5. Covers
   **both** Supabase projects (Finance is a separate project). Then delete `config.js`.

**Supabase email template must be fixed first.** Auth → Email Templates → *Magic link or OTP* only
contains `{{ .ConfirmationURL }}`, so it sends a link and no code. Add `{{ .Token }}`:

```html
<h2>Nudge sign-in</h2>
<p>Enter this code in the Nudge app:</p>
<p style="font-size:28px;letter-spacing:4px;"><strong>{{ .Token }}</strong></p>
```

Rate limit is ~2 emails/hour on the free tier, and **magic links are single-use** — one click burns
it (we watched a Mac click return `otp_expired` after the iPhone had already redeemed it). A `{{ .Token }}`
code can be typed into several clients before it expires, so the template fix turns 2 sends into 1.

### Engineering, in priority order
- ~~**D1 — whole-blob last-write-wins sync.**~~ ✅ **FIXED 2026-07-10.** Shipped as one cloud row per
  reminder/list/smart-list with `deleted_at` tombstones and a per-item merge. Deployed to both devices,
  two-device delete test passed. Spec of record: `D1_SYNC_DESIGN_per-reminder-merge.md` **§11**
  (§1–10 are the original design and are wrong in five places). Migration: `supabase/d1/`.
  Still open: schedule `04_purge_tombstones.sql`; do NOT run `05_retire_nudge_data.sql` before ~2026-07-24.
- **S3 runtime verification** — snooze a routine, wait 30 min, confirm its early alert reschedules.
- **D3** — `dismissed` is never set by any writer, but iOS filters on it.
- **D4/D5/D6** — were web-vs-iOS parity bugs. **Mostly moot now the web app is retired.** Re-read
  before spending time on them.
- Porting S1/S2 to the web sync path — **no longer needed.**

---

## 5. Project rules
- Confirm understanding before building; ask if <100% sure. Safety & security first.
- Never ask Noah to paste keys/API keys into chat. Anon user IDs (uuid) are fine; anon keys,
  `service_role`, passwords, `user_key` are not. Noah types his own OTP codes.
- **Deploy to BOTH iPhone and Mac after every change**, without being asked: `./reinstall_nudge.sh`.
  Preflight refuses if the iPhone is locked — unlock it first.
- Cowork cannot commit to this `.git` (lock permission). Commits happen via Claude Code. Clear stale
  locks with `rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true`.
- "Change web + iOS together" — **obsolete**, there is no web app now.
