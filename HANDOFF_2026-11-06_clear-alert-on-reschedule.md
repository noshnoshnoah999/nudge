# Handoff — 2026-11-06 — clear old notification when a reminder is moved

## Noah's request and decisions
- Rescheduling a reminder to a later time/day must remove the already-shown notification, in the same step as the save.
- Applies to EVERY way of moving (edit sheet, Reschedule button, notification "Reschedule…", bulk move, Smart Reschedule, Move Over, timetable drag).
- Early alerts: clear the old one too; re-send the early alert for the new time if there is still time (existing scheduler already does this).
- Moving earlier: clear too.
- Other device: clear on next sync (not instant — notifications are per-device).
- Repeating/routines: only that occurrence's alert.

## Status
- Code edited by Cowork in `NudgeStore.swift` + `Notifications.swift`. NOT committed/built yet → `CLAUDE_CODE_PROMPT_2026-11-06_clear-alert-on-reschedule.md`.

## Deliberate exclusions
- Prep reminders (`prepFor`) are moved automatically by `syncPrepReminders()` right after they fire; the backstop ignores them so their banner survives. Side effect: if you move a routine and its prep follows, the prep's old banner (if any) is not auto-cleared.
- `~geo` location alerts are never touched.

## Not changed (found during review, separate issue)
- `reschedule(_:to:)` / bulk move / Smart Reschedule do not re-arm the AlarmKit alarm for an "urgent" reminder; only the edit sheet does. An urgent reminder moved another way may ring at the OLD time. Not fixed — ask Noah.

## Test checklist (iPhone + Mac)
1. Reminder due in 2 min, no early alert. Let it fire. Use Reschedule → tomorrow 9:00. Banner disappears from Notification Centre immediately.
2. Same, but move it via the edit sheet. Banner gone immediately.
3. Reminder due in 32 min with a 30-min early alert. Let the early alert fire. Move the reminder to +2 h. Early banner gone; a new early alert is scheduled for 1 h 30 min from now (Settings shows scheduled count; or just wait).
4. Bulk move 2 fired reminders to tomorrow. Both banners gone.
5. Cross-device: let a reminder fire on BOTH devices, move it on the Mac. Open Nudge on iPhone → banner clears within a few seconds of sync.
6. Edit only the TITLE of a fired reminder (time unchanged). Banner must STAY.
7. Snooze still works as before (banner cleared, re-alerts at snooze time).
8. Prep reminder (e.g. ginger ingredients) fires → banner must STAY after a minute even though the app rolls it to next cycle.
9. Location alert (arrive/leave) banner must stay after editing that reminder's time.
