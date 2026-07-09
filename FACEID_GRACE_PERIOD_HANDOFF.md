# Face ID grace period — handoff

Date: 2026-07-09
File changed: `ios/Nudge/Nudge/ContentView.swift` (uncommitted — needs Claude Code to commit/push, see below)

## What changed

Previously, Nudge locked and required Face ID every single time the app left the
foreground, no matter how briefly (even a few seconds). Now there's a 60-second
grace period:

- Leave the app and come back within 60 seconds → no Face ID prompt, resumes straight in.
- Leave the app for 60 seconds or more → locks as before, Face ID required.
- Applies on both iOS (`scenePhase`) and Mac Catalyst (`NSApplicationDidResignActive` /
  `DidBecomeActive` notifications) — same 60s threshold on both.

## How it works

- New `@State private var backgroundedAt: Date?` records the timestamp when the app
  leaves the foreground (`.background` on iOS, resign-active on Mac).
- On return to foreground, `shouldRelockAfterGracePeriod()` checks
  `Date().timeIntervalSince(backgroundedAt) >= 60`. If true, locks and prompts Face ID
  as before. If false, just clears the shield with no prompt.
- Grace period constant: `ContentView.lockGracePeriod = 60` (seconds) — change this one
  line to adjust the window.

## Security-relevant edge case (already handled)

If Face ID is cancelled or fails, `isLocked` stays `true`. If the user then quickly
backgrounds/foregrounds again within the grace window, the code does **not** silently
clear the lock — it always re-prompts when `isLocked` is already `true`, regardless of
elapsed time. The grace period only skips a *fresh* lock decision on an app that was
sitting unlocked when backgrounded; it never bypasses an incomplete authentication.
This was a bug caught and fixed during implementation, not a known issue.

Cold launch is unaffected — `lock()` still always requires Face ID on first open,
since there's no `backgroundedAt` yet.

## Not yet done

- Not committed to git (Cowork sandbox can't write to this repo's `.git` — see
  memory `nudge-git-commit-limitation`).
- Not built/tested on device or simulator from this session. Recommend a quick manual
  check on device: background <60s (should skip Face ID), background >60s (should
  prompt), and cancel Face ID then quickly reopen (should still prompt).

## Next step: hand this to Claude Code

Give Claude Code this prompt:

```
Remove any stale .git/index.lock in the Nudge repo (rm -f .git/index.lock), then
git add -A and commit the changes to ios/Nudge/Nudge/ContentView.swift with message
"Add 60s grace period before Face ID re-lock on foreground". Build the iOS target to
confirm it compiles, fix any errors, then git push. After pushing, remove any lock
files or stale locks left behind so the repo is clean for next time.
```
