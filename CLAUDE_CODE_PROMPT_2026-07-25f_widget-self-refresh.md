# Claude Code prompt — widget refreshes its own session (2026-07-25f)

## The problem

The widget showed "Can't sync". Noah opened the app and it **still** didn't sync. He also notes
this happened occasionally before today's changes — so it is a pre-existing bug, not a
regression from the background/confirmation work.

Root cause, from `NudgeWidgets/WidgetData.swift:50` (the old comment said so outright):

> "The extension never refreshes tokens; the app does that the next time it opens."

`NudgeFeed.fetch()` only called `AuthStore.load()`. Once the Supabase access token lapsed
(~1 hour) every widget request 401'd and the widget was stuck on "Can't sync" until the app was
launched — and `ensureSession()`, which does the refreshing, lives in `Nudge/Auth.swift`, which is
**app-target only**, so the extension could not call it.

This is exactly backwards for Noah's setup: the whole point is to avoid opening apps, and the
widget is his primary surface. The design broke hardest precisely when it was working as intended.

Secondary bug found while reading: `WidgetCompletion.complete()` had the same flaw, so a
tap-to-complete made with a stale token **silently did nothing** — the row fetch 401'd and the
guard returned with no feedback.

## The fix

New `ios/Nudge/Shared/SessionRefresh.swift` — refreshes an expired session from **either** target.
Wired into `NudgeFeed.load()` and `WidgetCompletion.complete()`.

### Safety — read this before changing anything in that file

Supabase **rotates** refresh tokens: using one issues a new one and retires the old after a short
reuse window. Three deliberate rules keep a race from signing Noah out:

1. **Never clears the session on failure.** `Nudge/Auth.swift:84` treats 400/401 as terminal and
   calls `AuthStore.clear()`. That's fine in the app, where the user is present. It would be
   harmful in a widget: losing a refresh race on a background timeline build would wipe a
   perfectly good session with no way to tell the user why. `SessionRefresh` leaves the Keychain
   untouched on every failure path. Worst case is "Can't sync" for one cycle — recoverable;
   being signed out is not. **Do not "improve" this by adding a clear-on-401.**
2. **One refresh at a time** via a short Keychain lock (20s, self-expiring so a suspended
   extension can't block refreshes permanently). Neither target caches the session in memory —
   `Auth.bearer()` and `AuthStore.load()` both hit the Keychain every call — so whoever refreshes
   writes the new session and the other picks it up.
3. **Only refreshes when actually stale**, gated on `Session.isFresh`. Fewer rotations, fewer races.

### Also: the failure states are now distinguishable

Signed-out and server-unreachable both used to read "Can't sync", which is what sent Noah to
reopen the app in a case where the app couldn't help. Now:

- `WLoadState` gains `.signedOut` alongside `.loaded` / `.failed`.
- `NudgeFeed.load() -> Outcome` returns `.ok` / `.signedOut` / `.unavailable`.
- Today widget: "Signed out — Open Nudge to sign in" vs "Can't sync — Will retry automatically".
- Small widgets: "sign in" vs "can't sync".

**This doubles as the diagnostic we're missing.** Whichever message appears tells us which of the
two causes Noah is actually hitting, which static reading could not determine.

## Files

**New — pbxproj registration ALREADY DONE, verified, do not redo:**
- `ios/Nudge/Shared/SessionRefresh.swift` → both targets, mirroring `AuthStore.swift`. Verified:
  no duplicate object IDs; exactly one entry in each Sources phase (app `3A9BD1EC…`, widget
  `6E30D814…`). All three of `SessionRefresh`, `WidgetPendingCompletionStore` and
  `WidgetBackgroundImageStore` now show 1/1 per phase.

**Modified:**
- `NudgeWidgets/WidgetData.swift` — `load() -> Outcome`; `fetch()` kept as a thin wrapper.
- `NudgeWidgets/NudgeWidgets.swift` — `.signedOut` state, `NudgeEntry.signedOut`, `build()`
  switches on the outcome, all three failure panels reworded.
- `Shared/CompleteReminderWidgetIntent.swift` — completion now refreshes the token first.
- `Nudge.xcodeproj/project.pbxproj`.

## What to do

1. `git diff` and review, including `project.pbxproj`.
2. Build widget extension + app. Watch for: `WLoadState` equality (three cases, no associated
   values, so `==` still synthesizes); exhaustive switches over the new `.signedOut` case.
3. Test on device — **this is the part that tells us what was actually wrong:**
   - Note which message the widget now shows. **"Signed out"** → the Keychain session was
     genuinely missing, and the real question becomes why the app didn't write one. **"Can't
     sync"** → a session exists but the server/refresh failed. Report which.
   - Force the expiry path: leave the widget untouched for over an hour without opening the app,
     then check it refreshes on its own instead of showing "Can't sync".
   - Confirm tap-to-complete still works after a long idle period (that was the silent no-op).
   - Confirm the two-tap confirmation still behaves (arm → confirm within 10s).
   - Confirm the background is still true black in tinted mode, and rows don't overflow. Don't
     regress `023dbb7` / `16d8f6f` / `f189086`.
   - **Sign-out safety check, important:** verify that a failed refresh does NOT sign Noah out.
     Put the device in Airplane Mode with a stale token, let the widget refresh a few times, then
     restore connectivity and open the app — he must still be signed in.
4. Commit, e.g.
   - `fix(widget): refresh expired Supabase session from the extension`
   - `feat(widget): distinguish signed-out from unreachable in failure states`
5. Push to `origin/main`.
6. **After committing and pushing, remove any locks or stale locks** (`.git/index.lock`, leftover
   Xcode DerivedData locks) so the next session starts clean.

## Safety notes

- This is **auth code**. Don't add token logging of any kind — no access tokens, no refresh
  tokens, not even truncated, to console or crash logs.
- No secrets in source. Don't add `kSecAttrSynchronizable` to any Keychain item here.
- Don't add a clear-on-401 to `SessionRefresh` (see rule 1 above).

## Report back

State plainly: (a) does the widget now show "Signed out" or "Can't sync", (b) does it recover on
its own after the token lapses without the app being opened, and (c) did the Airplane-Mode test
leave the session intact.
