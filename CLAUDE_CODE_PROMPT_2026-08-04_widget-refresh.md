# Claude Code prompt — 2026-08-04: notification-tap crash + widget refresh (build, test, commit, push)

Copy everything below into Claude Code from the repo root.

---

You are working in the Nudge repo. Two fixes are already written and uncommitted in the
working tree. Do **not** rewrite them — build, verify on device, commit as two separate
commits, push.

Full detail: `HANDOFF_2026-08-04_widget-refresh-and-notification-crash.md`. Read it first.

## Fix A — notification tap / Reschedule crash (`ios/Nudge/Nudge/Notifications.swift`)

**Diagnosed from five crash reports**, all `EXC_CRASH (SIGABRT)` with faulting-thread queue
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
resumption lands on the cooperative pool — so UIKit did its app-switcher-snapshot work off
the main thread and asserted. `handle()` being `@MainActor` didn't help; the crash is on the
way back out. It only hit *some* notifications because a `handle()` that never suspends
completes inline on main; one that awaits (`store.refresh()`, `persistNow()`) does not.

**Change:** both delegate methods converted from the `async` variant to the
**completion-handler** variant, with the body in `Task { @MainActor in ... completionHandler() }`.
`didReceive` is the crash fix. `willPresent` is precautionary — same hazard, not named in any
trace; it can be reverted independently if it causes trouble.

## Fix B — widget not refreshing after an edit (`ios/Nudge/Nudge/NudgeStore.swift`)

The widget reads its data from **Supabase over the network**
(`NudgeWidgets/WidgetData.swift` → `NudgeFeed.load()`), not from local storage.
`persist()` called `WidgetCenter.shared.reloadAllTimelines()` **immediately**, but the cloud
push is on a 700 ms debounce — so the widget fetched the OLD rows and was never reloaded
afterwards.

**Change:** eager reload removed from `persist()` and `restoreBackup()`; `push()` now reloads
only after a successful `pushAll()`. No reload on failure (the cloud still holds the old rows;
the dirty set survives for the next push).

## Tasks

1. `git status` / `git diff` — confirm only these two files are modified and the diffs match
   the descriptions above. If anything else is dirty, stop and report.
2. Build the iOS app scheme **and** the widget extension. The project is Swift 5 language mode,
   so `Sendable` complaints on the completion handlers should be warnings, not errors. Report
   any compile error with the exact message. Do **not** revert the change to make it build
   without telling me first.
3. Install on the connected iPhone.

### Test Fix A (the important one)
4. Set a reminder ~1 minute out. Lock the phone.
5. **Plain tap** the notification → app opens to that reminder, no crash. Repeat 5×.
6. **Long-press → Reschedule** → app opens with the reschedule sheet, no crash. Repeat 5×.
   This was the reliable reproducer — it is the key test.
7. **Long-press → Complete** and **→ Snooze** → still work without opening the app, change syncs.
8. Force-quit Nudge, repeat 5 and 6 from fully-quit (cold launch).
9. With Nudge **open in the foreground**, let a reminder fire → banner still appears
   (exercises the `willPresent` change).

### Test Fix B
10. Note the Today widget's top row on the home screen.
11. In the app, change a reminder's time so its Today position changes.
12. Without touching the widget, go to the home screen and wait ~2 s → widget shows the new
    order. Confirm the app's sync chip reads "Synced".
13. Repeat for: add a reminder, complete one, delete one.
14. Airplane Mode: edit a reminder offline → widget should NOT change (correct). Restore
    network → after the next successful push the widget catches up.

## Commits

Two separate commits, Fix A first.

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

```
Widget: reload timelines after a successful push, not before it

The widget reads its data from Supabase over the network, so the eager
reloadAllTimelines() in persist() woke the extension ~700ms before the
debounced push had uploaded anything. It re-fetched the old rows and was
never reloaded again — hence "the widget doesn't update until I force it".

The reload now fires in push(), after a successful pushAll(), when the new
rows actually exist in the cloud. No reload on failure (the cloud still holds
the old rows and the dirty set survives for the next push). restoreBackup()'s
duplicate eager reload is removed; it routes through persist() -> push().

Also reduces WidgetKit reload-budget burn: a burst of edits collapses into one
debounced push and therefore one reload.
```

Commit even if an on-device test fails, but **say clearly in your report which tests passed
and which did not**. Do not claim a test passed that you did not actually run.

15. Push to `main` on the remote.
16. **After committing and pushing, remove any git locks or stale locks**
    (e.g. `.git/index.lock`, `.git/refs/heads/*.lock`) so the next session starts clean.
    Confirm `git status` is clean and no lock files remain.

## Do NOT do in this session
- Do not remove the `onMain` (`DispatchQueue.main.async`) deferrals inside `handle()`, the
  `pendingColdTap` machinery, `NudgeSceneDelegate`, or `shouldSaveSecureApplicationState`.
  They are probably now unnecessary but they are harmless, and stripping them in the same
  change would muddy verification of the real fix. Separate session, once this is confirmed.
- Do not touch the GitHub Pages / web app — it is retired.
