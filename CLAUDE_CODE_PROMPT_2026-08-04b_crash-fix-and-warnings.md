# Claude Code prompt — 2026-08-04b (CONSOLIDATED)

Everything currently uncommitted in the Nudge repo, in one session:
the notification-tap crash fix, the Xcode warning cleanup, the missing Nudge scheme,
a `.gitignore` fix, and the backlog of untracked handoff docs.

Copy everything below into Claude Code from the repo root.

---

## ⚠️ READ THIS FIRST

1. **There is a stale `.git/index.lock`** (0 bytes, left by the previous session on
   2026-08-04 08:22). Delete it before any git command: `rm -f .git/index.lock`
2. **Do not discard uncommitted work.** The previous session was handed a prompt covering two
   fixes, committed one, and silently discarded the other file's changes (`Notifications.swift`
   was reset to HEAD and the fix was lost). It has now been rewritten — losing it twice would
   be expensive. **Do not run `git checkout`, `git restore`, `git stash`, or `git clean` on any
   tracked file.** If the working tree contains changes you did not expect, **stop and report
   them rather than cleaning them up.**
3. **Do not `git add -A` / `git add .`.** `ios/Nudge/build/` is ~479 MB of build artifacts.
   A `.gitignore` entry for it is part of this change, but stage files explicitly regardless.

Background reading: `HANDOFF_2026-08-04_widget-refresh-and-notification-crash.md`.

---

## State of play

Already committed and pushed — **do not redo**:
- `82862e8` — widget refresh fix (`NudgeStore.swift`): reload timelines after a successful
  push instead of before the debounced one.

Uncommitted, and the entire subject of this session:

**Modified (tracked):**
```
ios/Nudge/Nudge/ClaudeLink.swift
ios/Nudge/Nudge/ContentView.swift
ios/Nudge/Nudge/LocationPickerView.swift
ios/Nudge/Nudge/Notifications.swift          ← the crash fix
ios/Nudge/Nudge/ReminderCardView.swift
ios/Nudge/Nudge/ReminderScanner.swift
ios/Nudge/Shared/CompleteReminderWidgetIntent.swift
ios/Nudge/Shared/WidgetPendingCompletionStore.swift
.gitignore
```

**New / untracked, to be added:**
```
ios/Nudge/Nudge.xcodeproj/xcshareddata/xcschemes/Nudge.xcscheme   ← restores the missing scheme
ios/Nudge/Nudge.xcodeproj/xcshareddata/xcschemes/NudgeWidgets.xcscheme
~38 CLAUDE_CODE_PROMPT_*.md / HANDOFF_*.md docs from July–August sessions
handoffs/2026-07-15-payday-card-filter-CLAUDE-CODE-PROMPT.md
```

**Must NOT be committed:** `ios/Nudge/build/` (~479 MB). The `.gitignore` change covers it.

---

## Fix A — notification tap / Reschedule crash (`Notifications.swift`)

Diagnosed from five crash reports, all `EXC_CRASH (SIGABRT)`, all with faulting-thread queue
`com.apple.root.user-initiated-qos.cooperative` — the Swift concurrency pool, not main:

```
-[NSAssertionHandler handleFailureInMethod:...]
-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]
-[UIApplication _updateStateRestorationArchiveForBackgroundEvent:...updateSnapshot:...]
-[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]
@objc closure #1 in NotificationManager.userNotificationCenter(_:didReceive:)
libswift_Concurrency  completeTaskWithClosure
```

`userNotificationCenter(_:didReceive:)` was `nonisolated func ... async`. Swift's @objc thunk
calls UIKit's completion handler when the async function **returns**, and a `nonisolated`
resumption lands on the cooperative pool — so UIKit did its app-switcher-snapshot work off the
main thread and asserted. `handle()` being `@MainActor` didn't help: the crash is on the way
back out, not in.

Only *some* notifications crashed because a `handle()` call that never suspends completes
inline on the main thread, while one that awaits (`store.refresh()`, `persistNow()`) resumes on
the pool. That is why Reschedule reproduced reliably.

**Change:** both delegate methods converted from the `async` variant to the **completion-handler**
variant, with the body inside `Task { @MainActor in ... completionHandler() }`.
`didReceive` is the crash fix. `willPresent` is precautionary — same hazard, not named in any
trace — and can be reverted independently if it misbehaves.

## Fix B — Xcode warnings (was 14, expect 1 left)

| File | Warning | Change |
|---|---|---|
| `ClaudeLink.swift` | `preferredControlTintColor` deprecated in iOS 26.0 | Removed — no replacement exists, the system tints Safari's chrome itself. The now-dead `tint:` parameter on `SafariView` removed too, plus its two call sites (`ContentView.swift`, `ReminderCardView.swift`), rather than left as a silent no-op. **Visible change: in-app browser controls use the system tint, not Theme.violet.** |
| `LocationPickerView.swift` | `placemark` deprecated in iOS 26.0 | `item.placemark.coordinate` → `item.location.coordinate` |
| `ReminderScanner.swift` | 3 × Vision `Sendable` warnings | `@preconcurrency import Vision` (Xcode's own fix-it) |
| `CompleteReminderWidgetIntent.swift` | 4 × "Main actor-isolated static method … cannot be called from outside of the actor" | `enum WidgetReload` → `nonisolated enum` |
| `WidgetPendingCompletionStore.swift` | the other 4 of those 8 | `enum WidgetPendingCompletionStore` → `nonisolated enum` |

The actor warnings come from `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in the project, which
pins every unannotated type to the main actor. `CompleteReminderWidgetIntent.perform()` is not
main-actor isolated, so it couldn't reach them. Opting those two enums out is correct rather
than a workaround: both are pure Keychain (`SecItem*`) / `WidgetCenter` calls, both thread-safe,
neither holds mutable state. **These are errors, not warnings, under the Swift 6 language mode.**

Deployment target is **iOS 26.5**, so iOS 26.0 deprecations are replaced outright with no
availability gates.

### One warning deliberately NOT fixed — leave it alone

`NudgeWidgets.swift:503` — `'+' was deprecated in iOS 26.0: Use string interpolation on Text`.

The comment directly above that code explains the concatenated `Text` is load-bearing: it keeps
the row on a single line so `TodayWidgetView.rowLimit(for:)` agrees with reality and the
natural-width + mask trick works. That is the widget row-overflow bug fixed in `16d8f6f`. The
suggested replacement changes the layout path and the two segments need different fonts.
If it is ever addressed it needs its own session with an on-device overflow test.

## Fix C — the missing `Nudge` scheme

**Cause:** `Nudge.xcodeproj/xcshareddata/xcschemes/` contained only `NudgeWidgets.xcscheme`.
`Nudge.xcscheme` was absent and **has never been tracked in git**. Meanwhile
`xcuserdata/noahflouty.xcuserdatad/xcschemes/xcschememanagement.plist` (a) references
`Nudge.xcscheme_^#shared#^_`, expecting a shared scheme that doesn't exist, and (b) sets
`SuppressBuildableAutocreation` primary=true for **both** target UUIDs — which is exactly what
stops Xcode auto-recreating it. Hence Xcode's scheme picker offering only NudgeWidgets, and
Noah being unable to build and run the app on his iPhone.

**Fix:** `Nudge.xcscheme` hand-written into `xcshareddata/xcschemes/`, pointing at the Nudge app
target (`BlueprintIdentifier = 3A9BD1EF2FCE10E000E88354`, `BuildableName = Nudge.app`).
`project.pbxproj` untouched. Commit `xcshareddata/` so it stops going missing.

## Fix D — repo hygiene

- `.gitignore`: added `ios/Nudge/build/` (~479 MB of xcodebuild output that was neither ignored
  nor committed). A comment notes that `xcshareddata/` is deliberately *not* ignored — shared
  schemes belong in git, which is the whole point of Fix C.
- ~38 `CLAUDE_CODE_PROMPT_*.md` / `HANDOFF_*.md` files from July–August sessions have never been
  committed. Commit them as project documentation.

---

## Tasks

1. `rm -f .git/index.lock`, then `git status`. Confirm the modified/untracked files match the
   "State of play" list. **If anything else is modified, stop and report — do not discard it.**
2. Confirm `git status` no longer lists `ios/Nudge/build/` once the `.gitignore` change is in
   place. If it still appears, stop — do not commit it.
3. Open/reload the project in Xcode. Confirm the scheme picker now offers **Nudge** as well as
   NudgeWidgets, with Noah's iPhone as the destination.
4. Build the **Nudge** scheme for the iPhone. Report the warning count — expect **1** remaining
   (the `Text +` one, deliberately left). Report any compile **error** with its exact message.
   Do not revert a change to make it build without telling me first.
5. Install on the connected iPhone.

### Test Fix A — the important one
6. Set a reminder ~1 minute out. Lock the phone.
7. **Plain tap** the notification → app opens to that reminder, no crash. Repeat 5×.
8. **Long-press → Reschedule** → app opens with the reschedule sheet, no crash. Repeat 5×.
   This was the reliable reproducer. It is the key test.
9. **Long-press → Complete** and **→ Snooze** → still work without opening the app, change syncs.
10. Force-quit Nudge, repeat 7 and 8 from fully-quit (cold launch).
11. With Nudge **open in the foreground**, let a reminder fire → banner still appears (exercises
    the `willPresent` change). Complete a reminder on the Mac, then let its stale iPhone alert
    fire → still suppressed.

### Test Fix B
12. Widget tap-to-complete: tap a Today-widget row → struck-through with "tap again"; tap again
    within 10s → completes. Tap a different row while one is armed → the new row arms instead.
    This exercises the `nonisolated` changes — verify it, don't assume.
13. Open a `Claude - ` reminder so the in-app Safari sheet appears → opens and closes normally
    (controls system-tinted now, not violet — expected).
14. Scan a reminder from a photo (OCR) → still extracts text.
15. Pick a location for a geofence reminder → coordinate still resolves correctly.

### Regression check on the already-shipped widget fix
16. Change a reminder's time so its Today position changes → widget updates within ~2s without
    being forced.

---

## Commits — four, in this order, staged explicitly (never `git add -A`)

**1.** `ios/Nudge/Nudge/Notifications.swift`
```
Fix notification-tap crash: run the delegate completion handler on the main actor

userNotificationCenter(_:didReceive:) was a `nonisolated func ... async`.
Swift's @objc thunk invokes UIKit's completion handler when the async
function returns, and a nonisolated resumption lands on the cooperative
thread pool — so UIKit ran _updateSnapshotAndStateRestorationWithAction:
off the main thread and tripped an NSAssertionHandler failure (SIGABRT).

Five crash reports (2026-07-28 -> 2026-08-03) all show the identical stack
with faulting-thread queue com.apple.root.user-initiated-qos.cooperative.

handle() being @MainActor did not prevent it: the crash is on the way back
out, not on the way in. It only affected some notifications because a
handle() call that never suspends completes inline on the main thread,
while one that awaits (store.refresh, persistNow) resumes on the pool —
which is why Reschedule reproduced it reliably.

Switched to the completion-handler variant and pinned the work to
Task { @MainActor in ... completionHandler() }. willPresent gets the same
treatment as a precaution; it is the identical hazard but is not named in
any trace.

This also explains why shouldSaveSecureApplicationState = false never
helped: UIKit still runs the updateSnapshot: half regardless of that opt-out.
```

**2.** `ios/Nudge/Nudge.xcodeproj/xcshareddata/`
```
Restore the missing shared Nudge scheme

xcshareddata/xcschemes/ held only NudgeWidgets.xcscheme, so Xcode's scheme
picker offered no way to build and run the app itself. Nudge.xcscheme has
never been tracked in git, and xcschememanagement.plist sets
SuppressBuildableAutocreation for both targets, so Xcode would not recreate
it automatically.

Added Nudge.xcscheme pointing at the Nudge app target and committed
xcshareddata/ so it stops going missing. project.pbxproj is untouched.
```

**3.** `ClaudeLink.swift`, `ContentView.swift`, `ReminderCardView.swift`,
`LocationPickerView.swift`, `ReminderScanner.swift`, `CompleteReminderWidgetIntent.swift`,
`WidgetPendingCompletionStore.swift`
```
Clear Xcode warnings: iOS 26 deprecations and main-actor isolation

- ClaudeLink: preferredControlTintColor was deprecated in iOS 26 with no
  replacement (the system tints Safari's chrome itself). Removed, along with
  SafariView's now-dead tint: parameter and its two call sites, rather than
  leaving a no-op parameter behind. Safari controls now use the system tint.
- LocationPickerView: MKMapItem.placemark -> .location for the coordinate.
- ReminderScanner: @preconcurrency import Vision for the non-Sendable
  VNImageRequestHandler / VNRecognizeTextRequest captures.
- WidgetPendingCompletionStore and WidgetReload are now nonisolated. The
  project sets SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which pinned them
  to the main actor and put them out of reach of the non-isolated
  CompleteReminderWidgetIntent.perform() — an error under Swift 6. Both are
  pure Keychain and WidgetCenter calls with no mutable state, so opting out
  is correct rather than a workaround.

Deployment target is iOS 26.5, so the deprecated APIs are replaced outright
with no availability gates.

Leaves one warning unfixed on purpose: the deprecated Text + concatenation in
NudgeWidgets.swift is load-bearing for the single-line row-width mask, and
changing it risks reintroducing the row-overflow bug fixed in 16d8f6f.
```

**4.** `.gitignore` + the untracked `*.md` docs and `handoffs/`
```
Ignore ios/Nudge/build, commit the July-August handoff docs

ios/Nudge/build is ~479MB of xcodebuild output that was neither ignored nor
committed, one `git add -A` away from entering history. xcshareddata/ is
deliberately left un-ignored — shared schemes belong in git, which is what
the missing Nudge scheme was about.

Also commits ~38 CLAUDE_CODE_PROMPT_*.md / HANDOFF_*.md files from recent
sessions that were never added.
```

Commit even if an on-device test fails, but **state clearly in your report which tests passed
and which did not**. Do not claim a test passed that you did not actually run.

17. Push to `main`.
18. **After committing and pushing, remove any git locks or stale locks** (`.git/index.lock`,
    `.git/refs/heads/*.lock`) so the next session starts clean. Confirm `git status` is clean
    and no lock files remain. The previous session skipped this step — please actually do it.

---

## Do NOT do in this session
- Do not discard uncommitted work, and do not `git add -A`. See the top of this file.
- Do not "fix" the `Text +` warning in `NudgeWidgets.swift`.
- Do not commit `ios/Nudge/build/`.
- Do not remove the `onMain` (`DispatchQueue.main.async`) deferrals inside `handle()`, the
  `pendingColdTap` machinery, `NudgeSceneDelegate`, or `shouldSaveSecureApplicationState`.
  They are probably redundant now but harmless, and stripping them in the same change would
  muddy verification of the real crash fix. Separate session, once this is confirmed on device.
- Do not touch the GitHub Pages / web app — it is retired.
