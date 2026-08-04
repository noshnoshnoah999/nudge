# Claude Code prompt — 2026-08-04c: last warning + correcting the crash comments

Copy everything below into Claude Code from the repo root.

---

## ⚠️ First

1. `rm -f .git/index.lock` before any git command (a stale lock keeps reappearing).
2. **Do not run `git checkout` / `git restore` / `git stash` / `git clean` on tracked files.**
   A previous session silently discarded uncommitted work this way. If the tree has changes you
   did not expect, stop and report them.
3. Do not `git add -A` — `ios/Nudge/build/` is ~479 MB (now gitignored, but stage explicitly).

## Context

Both bugs from this session are **fixed and confirmed working on device by Noah**:
`611e37d` (notification-tap crash) and `82862e8` (widget refresh). This session is cleanup only.

## Change 1 — the last Xcode warning (`NudgeWidgets/NudgeWidgets.swift`)

`WidgetRowTitle.content` concatenated two `Text` values with `+`, deprecated in iOS 26.0.

Xcode's suggested fix-it (plain string interpolation) is **wrong** for this case: the two
segments need different fonts, and only the title takes the strikethrough. Rewritten using a
two-run `AttributedString` wrapped in a single `Text`, which reproduces the old rendering
exactly while preserving the property the view actually depends on — that it collapses to
**one** `Text`, single line, natural width, so `TodayWidgetView.rowLimit(for:)` stays honest and
the mask trick works. That single-Text constraint is what fixed the row-overflow bug in `16d8f6f`.

If `s.strikethroughStyle = Text.LineStyle.single` or `s.font = .system(...)` does not compile,
report the exact error rather than reverting — the attribute names are from the SwiftUI
attribute scope and may need a small adjustment.

## Change 2 — correct the comments that record the wrong crash cause

No behaviour change. `Notifications.swift` and `NudgeApp.swift` carried comments blaming the
notification crash on CATransaction commits inside UIKit's state-restoration window. That
diagnosis was wrong — the real cause was the delegate being `nonisolated async`, so its
completion handler ran off the main thread. Left uncorrected, those comments would send the
next reader down the same dead end that burned five previous attempts.

Corrected in three places, with the mechanisms **deliberately kept**:

- `AppDelegate.didFinishLaunchingWithOptions` — now records that `NudgeSceneDelegate` +
  `pendingColdTap` are **load-bearing**, not leftover workaround: the UN delegate is attached in
  `NotificationManager.attach()` from SwiftUI's `.task`, i.e. *after* `didFinishLaunching`
  returns, so UNUserNotificationCenter will not deliver a launch tap to it. Removing them would
  silently break tapping a notification while Nudge is fully quit.
- `shouldSaveSecureApplicationState` — notes it never fixed anything (UIKit runs the
  `updateSnapshot:` half regardless of the opt-out) and is kept only because it is harmless.
- `handle()` — notes the cold-launch branch is required because `nudge` genuinely is nil at
  that point, and that the `onMain` deferral is probably now redundant but is kept because it
  costs one runloop tick and removing it reopens a settled question.

## Tasks

1. `rm -f .git/index.lock`, then `git status`. Expect exactly three modified files:
   `ios/Nudge/Nudge/Notifications.swift`, `ios/Nudge/Nudge/NudgeApp.swift`,
   `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`. Anything else → stop and report.
2. **Product → Clean Build Folder**, then build the **Nudge** scheme for the iPhone.
   The issue navigator caches stale warnings across incremental builds — a clean build is the
   only trustworthy count. Expect **0 warnings**. Report any compile error verbatim.
3. Install on the iPhone.
4. **Widget row test — this is the one that matters**, because Change 1 touches the code path of
   the row-overflow bug fixed in `16d8f6f`:
   - Add a reminder with a **long** title (long enough to run past the widget's right edge).
   - Confirm the Today widget row shows it clipped cleanly at the right edge, no "…", nothing
     spilling outside the widget, no change in row height.
   - **Tap that row once** → it should render struck through with "  tap again" appended, still
     on ONE line, still the same row height, still clipped cleanly.
   - Confirm the number of visible rows does not change between armed and unarmed.
   - Tap again within 10s → completes.
   - Repeat with a short title to check the unarmed path still renders normally.
5. Quick regression: notification plain tap and long-press → Reschedule still open without
   crashing (Change 2 is comments only, but confirm nothing was disturbed).

## Commits — two, staged explicitly

**1.** `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`
```
Widget row: replace deprecated Text + with a two-run AttributedString

'+' on Text was deprecated in iOS 26.0. Xcode's suggested fix-it (string
interpolation) does not fit: the title and the "tap again" hint need
different fonts, and only the title takes the strikethrough.

Rewritten as a single Text built from an AttributedString with two runs,
which renders identically and, crucially, still collapses to ONE Text —
single line, natural width. That is the property TodayWidgetView.rowLimit(for:)
depends on and what fixed the row-overflow bug in 16d8f6f.

Clears the last remaining build warning.
```

**2.** `ios/Nudge/Nudge/Notifications.swift`, `ios/Nudge/Nudge/NudgeApp.swift`
```
Correct the comments recording the notification-crash cause

No behaviour change. Several comments blamed the notification-tap crash on
SwiftUI committing a CATransaction inside UIKit's state-restoration window.
That diagnosis was wrong: the real cause was the delegate being a
`nonisolated async` method whose completion handler therefore ran off the
main thread (fixed in 611e37d, confirmed on device).

Those comments would have sent the next reader down the same dead end that
five previous fix attempts took, so they now record the true cause and say
explicitly which mechanisms are load-bearing and which are merely harmless:

- NudgeSceneDelegate + pendingColdTap are REQUIRED. The UN delegate is
  attached from SwiftUI's .task, after didFinishLaunching returns, so
  UNUserNotificationCenter will not deliver a launch tap to it. Removing
  them would silently break notification taps from a fully-quit app.
- shouldSaveSecureApplicationState = false never fixed anything; UIKit runs
  the updateSnapshot: half regardless. Kept because it is harmless.
- handle()'s onMain deferral is probably redundant now, but is kept: it
  costs one runloop tick and removing it reopens a settled question.
```

6. Push to `main`.
7. **Remove any git locks or stale locks** (`.git/index.lock`, `.git/refs/heads/*.lock`) and
   confirm `git status` is clean before finishing.

## Do NOT
- Do not remove `NudgeSceneDelegate`, `pendingColdTap`, the `onMain` deferral, or
  `shouldSaveSecureApplicationState`. Change 2 is comments only, on purpose.
- Do not revert Change 1 to silence a compile error — report the error instead.
- Do not touch the GitHub Pages / web app; it is retired.
