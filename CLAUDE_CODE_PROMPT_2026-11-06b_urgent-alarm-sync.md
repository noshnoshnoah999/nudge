# Claude Code prompt — 2026-11-06b — urgent alarms follow the reminder's current time

Paste everything below the line into Claude Code, opened in the Nudge repo.

---

Cowork has already edited three files. Your job: review, commit, build, install, push. Do NOT rewrite the change.

## SAFETY RULES (read first)
- Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset` on anything.
- Stage ONLY:
  - `ios/Nudge/Nudge/AlarmService.swift`
  - `ios/Nudge/Nudge/Notifications.swift`
  - `ios/Nudge/Nudge/NudgeStore.swift`
- Leave `ios/Nudge/Nudge.xcodeproj/project.pbxproj` and `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md` alone (do not stage, revert or delete).
- This prompt + `HANDOFF_2026-11-06b_urgent-alarm-sync.md` MAY go in a separate "Docs:" commit.

## What changed (for your review)
Bug: an "urgent" reminder's AlarmKit alarm was only armed/moved from the edit sheet. Moving it any other way (Reschedule, bulk move, timetable drag, Smart Reschedule, Move Over, undo), snoozing it, or editing it on the Mac left the alarm at the OLD time. A repeating urgent reminder's next occurrence never got an alarm.

1. `AlarmService.swift`: `NudgeAlarms.schedule` now returns `Bool` (@discardableResult). New `@MainActor enum NudgeAlarmReconciler` keeps alarms matched to each reminder's current time (due, or a later snoozedUntil), using a UserDefaults ledger `urgentAlarmLedger` (id → "epoch|title") so only real changes touch AlarmKit. Timed reminders only. Leaves an alarm alone once its time has arrived and the reminder hasn't moved (ringing / snooze countdown). Cancels for completed, deleted, dismissed, un-urgented, moved-into-past, or widget-completed-not-yet-synced. Skips entirely if the reminder list is empty (not loaded yet).
2. `Notifications.swift`: new `reconcileAlarms()`; called at the top of `reschedule()`, and from `scheduleDebounced()` even when notifications are OFF (alarms are a separate permission; the old `guard enabled` was removed from the debounce and moved inside).
3. `NudgeStore.saveReminder`: the direct schedule/cancel block is replaced with `Task { await NotificationManager.shared.reconcileAlarms() }`. Completion/delete cancels are unchanged.
All AlarmKit code stays inside `#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)`.

## Steps
1. `git status` and `git diff` the three files; sanity-check against the above.
2. Build BOTH iOS and Mac Catalyst with the shared `Nudge` scheme (Mac must compile with the AlarmKit parts excluded). Fix only real compile errors (e.g. Swift 6 isolation/Sendable on the `@MainActor` closure), keep behaviour identical, and tell Noah exactly what you changed.
3. Commit the three Swift files: `Urgent alarms follow the reminder's current time (reconciler; covers every move, snooze and Mac edits)`
4. Optional docs commit for the prompt + handoff.
5. Install with `reinstall_nudge.sh` and confirm the REAL iPhone install result, then the Mac app.
6. `git push`.
7. Remove stale git locks (`.git/*.lock`, any `*.lock` under `.git/`) ONLY if `pgrep -fl git` shows no git process.
8. Report: commit hashes, iOS + Mac build results, install result, push result.
