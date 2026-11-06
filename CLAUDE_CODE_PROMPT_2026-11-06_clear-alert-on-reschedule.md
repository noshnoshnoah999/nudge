# Claude Code prompt — 2026-11-06 — clear old notification when a reminder is moved

Paste everything below the line into Claude Code, opened in the Nudge repo.

---

Cowork has already edited two files in the Nudge repo. Your job: review, commit, build, install, push. Do NOT rewrite the change.

## SAFETY RULES (read first)
- Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset` on anything. Earlier, uncommitted work was lost that way.
- Stage ONLY these two files:
  - `ios/Nudge/Nudge/NudgeStore.swift`
  - `ios/Nudge/Nudge/Notifications.swift`
- Leave `ios/Nudge/Nudge.xcodeproj/project.pbxproj` (Xcode re-ordered one line) and `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md` alone: do not stage, revert or delete them.
- This prompt file and `HANDOFF_2026-11-06_clear-alert-on-reschedule.md` MAY be committed in a separate "Docs:" commit.

## What changed (for your review)
Goal (Noah): when a reminder is moved to a new date/time, any notification already shown for it is removed in the same step as the save; the new time (and its early alerts, if there is still time) is scheduled as normal.

1. `NudgeStore.clearNotifications(for:extraOffsets:)` now removes the due-time alert AND every early alert (`nudge-<id>~e<min>`), pending + delivered. `~geo` alerts untouched.
2. It is now called whenever a reminder is moved: `reschedule(_:to:)` (Reschedule options, notification "Reschedule…", bulk move, timetable drag), `applyReschedule` (Smart Reschedule), AI move-over, `undoReschedule`, and `saveReminder` when the due instant changes by ≥ 60 s or is added/removed (edit sheet; also "this occurrence only"). On a move, `saveReminder` also clears `snoozedUntil`, so a stale snooze can't hold back the new early alerts.
3. Backstop in `NotificationManager.clearStaleDelivered()`: new `movedSinceDelivered(...)` marks a delivered alert stale when its expected fire time (due, or max(due, snoozedUntil) for the main alert; due − offset for early alerts) is more than 120 s away from when it was delivered. This makes the OTHER device (Mac/iPhone) clear its copy on next sync. Excluded: prep reminders (`prepFor != nil`, which `syncPrepReminders()` rolls forward automatically right after they fire), `~geo` alerts, unknown suffixes, payday, birthdays, Tsuji.

## Steps
1. `git status` and `git diff -- ios/Nudge/Nudge/NudgeStore.swift ios/Nudge/Nudge/Notifications.swift`. Sanity-check the diff matches the above.
2. Build BOTH the iOS app and the Mac (Catalyst) app with the shared `Nudge` scheme. Fix only real compile errors, keeping the behaviour identical, and tell Noah exactly what you changed.
3. Commit:
   `git add ios/Nudge/Nudge/NudgeStore.swift ios/Nudge/Nudge/Notifications.swift`
   Message: `Clear old notification when a reminder is moved (incl. early alerts, cross-device backstop)`
4. Optional second commit: `git add CLAUDE_CODE_PROMPT_2026-11-06_clear-alert-on-reschedule.md HANDOFF_2026-11-06_clear-alert-on-reschedule.md` → `Docs: clear-alert-on-reschedule prompt and handoff`.
5. Install on iPhone with `reinstall_nudge.sh` and check the REAL device install result (that script has given false success before), then run the Mac app.
6. `git push`.
7. Finally remove any stale git locks so next time is smooth: delete `.git/index.lock`, `.git/HEAD.lock`, and any other `*.lock` under `.git/` ONLY if no git process is running (`pgrep -fl git` first).
8. Report: commit hashes, build results for iOS + Mac, install result, push result.
