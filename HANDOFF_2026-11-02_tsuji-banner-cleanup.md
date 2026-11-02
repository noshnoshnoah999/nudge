# Handoff — 2026-11-02: Tsuji Action Banner — DONE (cleanup)

This is the final handoff for the Tsuji Action Banner. Earlier files, oldest first:
`TSUJI_ACTION_BANNER_SPEC.md` (spec), `HANDOFF_2026-10-29_tsuji-banner.md`,
`HANDOFF_2026-11-01_tsuji-banner-step2.md`, `HANDOFF_2026-11-02_tsuji-banner-step3.md`.
Where they differ, the newest wins.

## Result

All tests passed on iPhone and Mac:
- **Step 1 (Test 0)**, 1 Nov: Nudge finds all 13 events by UID on both devices.
- **Step 2** (saving off), 2 Nov: banner, typed clear, safety refusals, missing row, notifications,
  access-off message — all passed.
- **Step 3** (saving on), 2 Nov:
  - Test 5 clear: #1 got `COMPLETED – `, a `Completed in Nudge on 2026-11-02` note, alerts removed;
    Calendar did not re-add a default alert; stayed cleared after force-quit.
  - Test 6 undo (title prefix deleted in Calendar): #1 reopened, `Reopened in Nudge on 2026-11-02`
    added, alerts restored as exactly −572400 s and +32400 s (the iPhone's duplicate on-day alert
    was dropped, as agreed).
  - Test 6c: Mac showed #1 open. Test 7: a date change in Calendar was followed both ways.
- #1 now ends with two extra note lines and two alerts. That's expected and agreed.

## Cleanup (commit `9bad9d9`, not built yet)

Removed: Test mode (toggle, pretend date, made-up and open-campus test entries, Test tools
screen, safety self-test, sample/pending notification helpers, TEST MODE label, "[TEST]"
wording). Old Test mode settings are deleted once on launch.

Kept on purpose (Noah, 2 Nov 2026):
1. **`TsujiPlan.calendarWritesEnabled`** (currently `true`) as an emergency off switch. Setting it
   to `false` stops all Calendar edits; clears then happen inside Nudge only and are forgotten,
   never written, when it's switched back on.
2. **Settings → Tsuji plan → Calendar ID check** — read-only diagnostic. It still looks for the
   `tsuji-plan-01-` prefix, only to confirm Nudge can see that event's invitee (its safety
   line). The UID 01 test-entry constant is gone from the app code.

## How the feature works now

- Banner on Home (under birthdays) and at the top of Today, iPhone + Mac. Shown only when an item
  is overdue, due within 7 days, or missing from the calendar. "Now" + "Next steps", collapsible.
- Settings → Tsuji plan → **Plan** lists all 13 with status; tap for the details sheet.
- Clearing: only via the clear sheet, typing `Confirmed and completed` (shown on screen).
- Undo: delete `COMPLETED – ` from the event title in Calendar.
- Notifications: 09:00 on the due date, then daily until cleared, 7 days ahead, only in slots
  left after normal reminders (64 max).
- Adding a new action event later: add its UID (`tsuji-plan-NN-YYYYMMDD@noah.flouty.uk`) to
  `TsujiPlan.actionUIDs` — never UID 01 or any of the other non-action events.

## Known, accepted limits

- Apple's per-device default alert (iPhone: on the day; Mac: 1 day before) can't be recreated as a
  "default" after an undo; the two real alerts are restored.
- If two copies of an event exist in Tsuji Plan, Nudge shows an error row instead of guessing.

## Next

Claude Code: build, install, push (`CLAUDE_CODE_PROMPT_2026-11-02_tsuji-cleanup.md`).
Noah: check that Settings → Tsuji plan shows only **Plan** and **Calendar ID check** (no Test
mode), and the Plan list still shows the 13 items.
