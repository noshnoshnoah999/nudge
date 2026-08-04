# Handoff — 2026-08-04: Widget refresh race + notification-tap crash

> **FINAL STATUS — session closed 2026-08-04. Everything below is DONE, committed, pushed,
> and confirmed working by Noah on both iPhone and MacBook. Build is at 0 warnings.**
>
> | Commit | What |
> |---|---|
> | `82862e8` | Widget refresh race — reload timelines after the push, not before |
> | `611e37d` | Notification-tap crash — delegate completion handler on the main actor |
> | `deac668` | Restored the missing shared `Nudge.xcscheme` |
> | `d3ee7ae` | Xcode warnings: iOS 26 deprecations + main-actor isolation (14 → 1) |
> | `6bd0dd6` | Gitignore `ios/Nudge/build/` (479 MB); commit the July–August docs |
> | `3fe935d` | Widget row: deprecated `Text +` → two-run `AttributedString` (1 → 0) |
> | `e1932b1` | Correct the comments that recorded the wrong crash cause |
>
> **The one lesson worth carrying forward:** the notification crash survived five previous
> fix attempts because every one of them addressed *where the work started* (`pendingColdTap`,
> the `onMain` deferral, `shouldSaveSecureApplicationState`). The five crash reports showed
> the fault was *where the method returned* — a `nonisolated async` @objc delegate resumes on
> the cooperative thread pool, so UIKit's completion work ran off the main thread. Five
> identical stack traces settled in minutes what months of reasoning had not. **When a bug
> resists more than one or two fixes, stop theorising and go get the evidence.**
>
> Residual checks (low priority, not blocking):
> - Analytics Data in a few days — no new `Nudge-*.ips` is the durable proof.
> - A long-titled reminder on the Today widget, tapped once to arm: confirm it stays on one
>   line, clips cleanly, and the visible row count doesn't change. `3fe935d` changed the width
>   measurement path, and measurement is what the `16d8f6f` overflow bug was about.
>
> Deliberately NOT removed, and why — see the comments now in the code:
> `NudgeSceneDelegate` + `pendingColdTap` are **load-bearing**, not leftover workaround. The UN
> delegate is attached from SwiftUI's `.task`, after `didFinishLaunching` returns, so
> UNUserNotificationCenter will not deliver a launch tap to it. Deleting them would silently
> break notification taps from a fully-quit app — with no crash, so you'd find out days later.

---

## Bug 2 — Widget not refreshing after an edit — FIXED (needs build + on-device test)

### Symptom
Noah moved "pay amazon subscribe & save" from 1st to 3rd in Today and changed its time.
The Today widget on the iPhone home screen kept showing the old order/time. It only
updated after he forced a refresh by toggling a setting in the widget's edit sheet.

### Root cause (confirmed by reading the code, not guessed)
The widget does **not** read local data. `NudgeWidgets/WidgetData.swift` → `NudgeFeed.load()`
fetches reminders and lists straight from the per-item **Supabase** tables over the network
(this has been true since the Jul 24 "false All clear" rewire).

`NudgeStore.persist()` did this, in this order:

1. `writeCache()` — local only
2. schedule the cloud push on a **700 ms debounce** (`pushTask`)
3. `WidgetCenter.shared.reloadAllTimelines()` — **immediately**

So the reload request went out ~700 ms *before* the edit was uploaded. WidgetKit woke the
extension, it hit Supabase, got the **old** rows, rendered them — and nothing ever reloaded
it again. `push()` never called `reloadAllTimelines()`. Result: stale widget until some
unrelated event kicked it.

Secondary cost: every persist burned one of WidgetKit's limited daily reloads (~40–70) on a
fetch that could only ever return stale data, making real throttling more likely later in the day.

### Fix
`ios/Nudge/Nudge/NudgeStore.swift`

- **`persist()`** — removed the eager `reloadAllTimelines()`. Replaced with a comment
  explaining why it must not be there.
- **`push()`** — added `if ok { WidgetCenter.shared.reloadAllTimelines() }` after a
  successful `pushAll()`. This is the first moment the new rows actually exist in the cloud.
  On failure we deliberately do **not** reload (cloud still holds old rows; the dirty set
  survives and the next successful push reloads).
- **`restoreBackup()`** — removed its own eager reload; it calls `persist()`, which now
  routes through `push()`.
- `persistNow()` (used by notification Complete/Snooze) calls `push()`, so it inherits the
  fix for free.

Untouched and still correct:
- `NudgeStore.swift:223` — reload after a **pull** when `outcome.changed`. Cloud is already
  authoritative there.
- `Shared/CompleteReminderWidgetIntent.swift` — writes to Supabase *then* reloads. Correct order.
- `SyncSettingsView.swift` (sign-in) and `WidgetBackgroundView.swift` (local widget prefs).

### Expected behaviour after this ships
Edit a reminder → ~700 ms debounce + one network round-trip → widget reloads with the new data.
Typically 1–2 seconds. No more manual force-refresh.

### Honest caveat
`reloadAllTimelines()` is a *request*, not a command. WidgetKit still applies a daily budget
and can defer a reload under low power / heavy system load. This change makes reloads
**correct** and **fewer** (a burst of edits collapses into one debounced push → one reload),
which reduces throttling risk — but it cannot make WidgetKit guarantee instant updates.
If Noah still sees lag after this, the next step is measuring actual reload budget, not
adding more reload calls.

### Test plan (on device, iPhone)
1. Build + install.
2. Note the Today widget's current top row.
3. In the app, change a reminder's time so its position in Today changes.
4. Do **not** touch the widget. Go to the home screen and wait ~2 s.
5. Widget should show the new order. Confirm the app's sync chip reads "Synced".
6. Repeat with: adding a new reminder, completing one, deleting one.
7. Offline test: turn on Airplane Mode, edit a reminder. Widget should NOT change
   (correct — cloud still has the old row). Turn Wi-Fi back on; on the next successful
   push the widget should catch up.

---

## Bug 1 — Notification tap / Reschedule crashes the app — DIAGNOSED + FIXED (needs build)

### Symptom
Tapping *some* Nudge notifications launches the app; it crashes under a second later.
Long-press → **Reschedule** does the same. Complete / Snooze (which do not open the app)
are fine.

### Evidence
Five crash reports supplied by Noah, all on iPhone18,1:

| File | iOS | procRole | faulting-thread queue |
|---|---|---|---|
| `Nudge-2026-07-28-084233.ips` | 26.5.2 | unknown | `com.apple.root.user-initiated-qos.cooperative` |
| `Nudge-2026-07-31-130718.ips` | 26.5.2 | unknown | `com.apple.root.user-initiated-qos.cooperative` |
| `Nudge-2026-08-02-171325.ips` | 26.6 | unknown | `com.apple.root.user-initiated-qos.cooperative` |
| `Nudge-2026-08-03-085424.ips` | 26.6 | Foreground | `com.apple.root.user-initiated-qos.cooperative` |
| `Nudge-2026-08-03-121013.ips` | 26.6 | Foreground | `com.apple.root.user-initiated-qos.cooperative` |

All five: `EXC_CRASH (SIGABRT)`, `abort() called`, identical stack:

```
-[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:]
-[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]
-[UIApplication _updateStateRestorationArchiveForBackgroundEvent:saveState:
                exitIfCouldNotRestoreState:updateSnapshot:windowScene:]
-[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]
@objc closure #1 in NotificationManager.userNotificationCenter(_:didReceive:)   ← our code
thunk for @escaping @isolated(any) @callee_guaranteed @async () -> ()
libswift_Concurrency  completeTaskWithClosure
```

### Root cause (CONFIRMED, not a hypothesis)
`com.apple.root.user-initiated-qos.cooperative` is the **Swift concurrency thread pool**, not
the main thread. UIKit is being asked to refresh the app-switcher snapshot / state-restoration
archive off the main thread, and it trips an `NSAssertionHandler` failure → SIGABRT.

Why it ran off-main: `userNotificationCenter(_:didReceive:)` was declared
`nonisolated func ... async`. Swift wraps an `async` @objc delegate method in a thunk that
calls UIKit's completion handler **when the async function returns**. Because the method was
`nonisolated`, that final resumption landed on the cooperative pool — so UIKit's completion
work ran there.

`handle()` being `@MainActor` did not help: it hops *to* main correctly. The crash is on the
way back **out**.

**Why only some notifications:** if `handle()` returns without ever suspending (a plain tap
that hits an early `return`), the whole call completes inline on the main thread and there is
no crash. If it actually awaits — `store.refresh()`, `persistNow()`, any network I/O — the
continuation resumes on the pool and it crashes. That is why **Reschedule reproduced reliably**.

**Why the earlier fixes never worked:** `AppDelegate.shouldSaveSecureApplicationState = false`
opts out of the *restoration archive*, but UIKit still runs the `updateSnapshot:` half of
`_updateSnapshotAndStateRestorationWithAction:` regardless. The `pendingColdTap` machinery and
the `onMain` one-tick deferral were both aimed at the wrong thing — they addressed *where the
work started*, when the bug was *where the method returned*.

**Hypotheses now dead:** the `LockShield` / Face ID window collision, and the sheet-presentation
race. Neither appears anywhere in any of the five traces. App lock is irrelevant to this crash.

### Fix
`ios/Nudge/Nudge/Notifications.swift`

- `userNotificationCenter(_:didReceive:)` — replaced the `async` variant with the
  **completion-handler** variant `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
  It extracts `actionIdentifier` and the notification id up front (`UNNotificationResponse` is
  not Sendable), then runs `Task { @MainActor in await handle(...); completionHandler() }`.
  Because we own the Task and pin it to `@MainActor`, UIKit's snapshot work is guaranteed to
  run on the main thread.
- `userNotificationCenter(_:willPresent:)` — same conversion. **PRECAUTIONARY**: this method is
  not named in any crash report, but it is the identical hazard (`nonisolated async` that
  awaits `store.refresh()` network I/O). Behaviour unchanged. If the build has trouble, this
  one can be reverted independently of the `didReceive` fix.

An extensive comment block is left above `didReceive` recording the trace and the reasoning,
so nobody "simplifies" it back to `async`.

### Deliberately NOT changed
- The `onMain` (`DispatchQueue.main.async`) deferrals inside `handle()` — now probably
  unnecessary, but harmless, and removing them in the same change would muddy verification.
  Revisit once the fix is confirmed on device.
- `pendingColdTap` / `NudgeSceneDelegate` / `shouldSaveSecureApplicationState`. Same reasoning.

### Test plan (on device, iPhone)
1. Build + install. Confirm the two delegate methods compile without actor-isolation errors
   (project is Swift 5 language mode, so Sendable complaints are warnings, not errors).
2. Set a reminder for ~1 minute out. Lock the phone.
3. **Plain tap** on the notification → app opens to that reminder, no crash. Repeat 5×.
4. **Long-press → Reschedule** → app opens with the reschedule sheet, no crash. Repeat 5×.
   This was the reliable reproducer, so it is the key test.
5. **Long-press → Complete** and **→ Snooze** → still work, no app launch, change syncs.
6. Force-quit Nudge, then repeat 3 and 4 from a fully-quit state (cold launch).
7. With Nudge **open in the foreground**, let a reminder fire → banner still appears
   (this exercises the `willPresent` change). Complete a reminder on the Mac, then let its
   stale iPhone alert fire → it should still be suppressed.
8. Re-check Analytics Data after a day: no new `Nudge-*.ips`.

---

## Files changed
- `ios/Nudge/Nudge/NudgeStore.swift` — widget refresh race
- `ios/Nudge/Nudge/Notifications.swift` — notification-tap crash

## Not done
- No commit (Cowork cannot write to the Nudge `.git` — see `CLAUDE_CODE_PROMPT_2026-08-04_widget-refresh.md`).
- No build. Xcode build + on-device test must happen in Claude Code.
