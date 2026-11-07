# Handoff — 2026-11-07 — "Pin from a date"

Status: CODE WRITTEN in Cowork, NOT built, NOT committed. Claude Code prompt:
`CLAUDE_CODE_PROMPT_2026-11-07_pin-from-date.md` (review → build iOS + Mac → commit → install → push).
Base: HEAD 49ae36b (clean working tree before this change).

## Noah's request
Pinned reminders that aren't needed yet (e.g. due in a month) should only appear in Home's
PINNED section from a chosen date.

## Agreed rules
- "Pin from a date" toggle under "Pin to Home", date only. Available only when due is tomorrow or later; range tomorrow…due day.
- Card label "Pins d MMM" until the day.
- Moving to another day with a pending pin: Keep (hidden if after new due) / Shift by same amount / Pick new date. Edit screen + Reschedule per reminder; Bulk Move once per batch. Snooze + automatic move-over don't ask.
- Moved to today: warning, then straight to Pinned (pin day cleared).
- Repeating: "This reminder only" (next occurrence pinned straight away) / "All future ones too" (same gap before each due date). Existing repeating reminders use the existing This Event / Future Events dialog.

## Data
`Reminder.pinFrom` (ISO start of day) + `pinFromGapDays` — optional JSON fields, no schema change.
Effective rule: `pendingPinDay` = min(pin day, due day) if still in the future; otherwise pinned now.

## Files
New `Nudge/PinFrom.swift`; edited Models, NudgeStore, AddReminderView, RescheduleOptionsView,
BulkMoveView, ReminderCardView, RemindersSync, Changelog (2.33), Shared/RecurrenceEngine,
Shared/CompleteReminderWidgetIntent.

## Known limits / deliberate choices
- Timetable drag, Smart Reschedule, move-over not wired (they never change the day of an item with a pending pin); store normalisation keeps them safe anyway.
- Bulk Move "Pick a new date" uses one date for all affected reminders, capped at the earliest new due day.
- Snooze to a later day keeps the pin day (clamped to the due day by `pendingPinDay`).
- Widget doesn't show pins, so no widget UI change.
