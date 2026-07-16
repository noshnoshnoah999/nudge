# Handoff — Pay Day card filtering fix
**Date:** 2026-07-15
**Made by:** Cowork (Claude)
**Status:** Code changed, NOT yet built or committed

## What changed
`ios/Nudge/Nudge/NudgeStore.swift` — `buyReminders()` (around line 484).

**Before:** returned every open Shopping-list reminder, regardless of due date, sorted soonest first.

**After:** only returns open Shopping-list reminders whose `dueDate` is on payday itself (`Payday.inMonth(Date())` — the 15th, or the preceding Friday if the 15th falls on a Sat/Sun).

## Why
The Home screen "PAY DAY · X TO BUY" card (`ContentView.swift` ~line 447-471) was showing the entire Shopping list (10 items, due across mid-July to mid-August) instead of just the items actually due on pay day. Noah wants the card to only surface what needs buying today.

## Decision locked with Noah
Shopping reminders due on *other* days should NOT appear in this card at all — they stay visible in the normal Shopping list / Today / Upcoming views only. No fallback behavior if zero items are due on payday — the card just doesn't render (existing `if !buys.isEmpty` check already handles this, untouched).

## Not yet done
- Not built/compiled — Cowork sandbox can't run Xcode. **Claude Code must build and confirm no compile errors** before committing.
- Not committed or pushed.
- No test coverage added — worth a quick manual check on device/simulator: set a Shopping reminder's due date to today's payday date, confirm it shows in the card; confirm other-dated Shopping reminders do NOT show.

## Files touched
- `ios/Nudge/Nudge/NudgeStore.swift` (modified)

## Relevant context
- `Payday.swift` has the payday date logic (15th, shifted for weekends). Untouched, just consumed here.
- `ContentView.swift` dashboardTab (~line 443-471) renders the card; no changes needed there — `.isEmpty` check and `.count` label already adapt correctly to the new filtered result.
