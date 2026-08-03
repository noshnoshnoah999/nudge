# Claude Code Prompt — Cross-device appearance sync (theme/boldText/compact) — 2026-07-24e

## What this feature does

Sync **theme, boldText, and compact** across the user's signed-in devices (iPhone ⇄ MacBook). celebrationFeedback, appLock, and upcomingSections stay DEVICE-LOCAL on purpose. Conflict rule: **most-recent-write-wins** (whichever device changed last).

## Why it's low-risk (reused existing infra)

Nudge already has a dormant per-user Supabase `settings` row (single row, whole-value, ordered by `updated_at`), pulled in `NudgeStore.pullAll` and pushed in `pushAll` — but nothing wrote into it. This change wires AppSettings into that existing row. **No new table, no new migration, no new conflict logic, no new secrets.**

## Files changed in Cowork (already edited — NOT built)

1. **`ios/Nudge/Nudge/Models.swift`** — `enum JSONValue` now also conforms to `Equatable` (needed to compare settings values; safe synthesized conformance).

2. **`ios/Nudge/Nudge/AppSettings.swift`** — rewritten:
   - `theme`, `boldText`, `compact` didSet now also call `pushAppearanceIfLocal()`.
   - `applyingFromCloud` guard flag prevents the ping-pong loop (cloud→apply→push→pull→…).
   - `attach(_ store:)` (mirrors sync/notifier.attach): adopts current cloud appearance, seeds cloud if empty, registers `store.onCloudAppearance` callback.
   - `applyFromCloud(theme:boldText:compact:)` applies cloud values under the guard, only when different.

3. **`ios/Nudge/Nudge/NudgeStore.swift`**:
   - New `onCloudAppearance` callback property.
   - `pullAll`: after adopting a NEWER settings row, calls `onCloudAppearance` with `cloudAppearance()`.
   - New bridge methods: `applyLocalAppearance(theme:boldText:compact:)`, `seedAppearanceIfMissing(...)`, `cloudAppearance()`. Keys: "theme"/"boldText"/"compact".

4. **`ios/Nudge/Nudge/NudgeApp.swift`** — `.task` now also calls `settings.attach(store)`.

Cowork verified braces/parens balance on the added blocks, but CANNOT compile. Your job is the build + the real test.

## Your job

1. **Build** the iOS + macCatalyst app. Fix any compile errors (I couldn't type-check).
2. **Two-device sync test** (the actual acceptance test):
   - Sign both devices into the same account.
   - Change the theme on device A → confirm device B adopts it (on next foreground/refresh, ~15s poll or reopen).
   - Change boldText and compact on device B → confirm device A adopts them.
   - **Ping-pong check:** after a change syncs, confirm it does NOT bounce back or flip-flop (the `applyingFromCloud` guard must hold). Watch for repeated settings uploads in logs.
   - **Most-recent-wins:** change theme on both close together; confirm the later change wins and both settle on it, no infinite churn.
3. If it all holds, commit:
   `feat(settings): sync theme/boldText/compact across devices via existing settings row`
   then push.

## Watch-outs (be skeptical here)

- **Feedback loop** is the #1 risk. If you see the two devices endlessly swapping themes, the guard isn't holding — check `applyFromCloud` sets/resets `applyingFromCloud` and that pushAppearanceIfLocal early-returns while it's set.
- **Launch ordering:** `attach` runs in `.task` before `refresh()` may have pulled the cloud row. That's intended — `cloudAppearance()` reads the local cache at attach, and the `onCloudAppearance` callback handles the later pull. Confirm a theme set on the OTHER device before this device launched still lands (via the post-refresh callback), not just live changes.
- **Seeding:** `seedAppearanceIfMissing` should only write if the cloud carries NONE of the 3 keys. Make sure a device with existing cloud appearance doesn't overwrite it on launch.

## After committing/pushing

Remove any git locks / stale locks (`.git/index.lock`, `.git/*.lock`) so the next session is smoother.
