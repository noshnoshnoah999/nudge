# Handoff — 2026-11-06b — urgent alarms follow the reminder's current time

## Decisions (made by Claude because Noah was busy; Noah can change)
- Snoozing an urgent reminder → the alarm rings again at the snooze time.
- Urgent reminder moved to a time already passed → its alarm is cancelled, no ring.

## Status
Edited in Cowork: AlarmService.swift, Notifications.swift, NudgeStore.swift. Not committed/built → CLAUDE_CODE_PROMPT_2026-11-06b_urgent-alarm-sync.md.

## Behaviour
- Every way of moving now moves the alarm (one shared reconciler, runs on every change, launch, foreground, sync).
- Edits on the Mac reach the iPhone alarm on the iPhone's next sync/open.
- Repeating urgent reminders: each next occurrence now gets its own alarm (previously none).
- Date-only urgent reminders still never ring (same as before).
- Works even if notifications are switched off.

## Known edge (one-time)
Alarms armed by older builds aren't in the ledger. If such a reminder was already moved into the past before this build, its old alarm may still ring once. Future-dated ones are re-armed correctly on first launch.

## Quick test (iPhone, when free)
1. Urgent reminder in 3 min → Reschedule to +5 min. Rings at the NEW time only.
2. Same via bulk move.
3. Edit time on the Mac → open Nudge on iPhone → rings at new time.
4. Complete an urgent reminder before its time → no ring.
5. Untick Urgent on one → no ring.
