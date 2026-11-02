# Handoff — 2026-11-02: Tsuji Action Banner, step 3 (Calendar saving ON)

Read with: `TSUJI_ACTION_BANNER_SPEC.md`, `HANDOFF_2026-10-29_tsuji-banner.md`,
`HANDOFF_2026-11-01_tsuji-banner-step2.md`. Newest handoff wins where they differ.

## Status

- Step 2: **every test passed** (Noah, 2 Nov 2026).
- Before step 3, Noah: turned Test mode off on both devices, **exported the Tsuji Plan calendar
  on the Mac as a backup**, and checked default all-day alerts: iPhone = "On the day";
  Mac = "None" (doesn't match the Mac's 1-day-before third alarm — possibly a different account
  selected in Mac Calendar → Settings → Alerts; Noah chose not to check further).
- Step 3: **`TsujiPlan.calendarWritesEnabled = true`, committed `12c69cb`, not built yet.**
  That one line is the only code change.

## What changes with saving ON

- Clearing an item with the typed phrase edits that ONE event: title gets `COMPLETED – `, notes
  get `Completed in Nudge on YYYY-MM-DD`, all its alerts are removed.
- Undo (delete `COMPLETED – ` from the title in Calendar): Nudge reopens it, restores the alerts
  from the clearing device's backup (exact duplicates skipped) and adds
  `Reopened in Nudge on YYYY-MM-DD`.
- Test entries (made-up UID, UID 01) can no longer appear. Step 2 dry-run clears are forgotten.
- Test mode's pretend date still works (useful for Test 7's banner check).

## Noah's step 3 test checklist — item #1 only

#1 = "Check open campus entry pass (参加証) has arrived", all-day, 9 Jan 2027.
It isn't in the banner until 2 Jan, so open it from **Nudge → gear → Tsuji plan → Plan → #1**.

**Before you start:** quit Nudge on the **Mac** (⌘Q) and keep it closed until Test 6 is done, so
only the iPhone acts on #1. Do everything below on the **iPhone**.

| # | Do | Pass if |
|---|---|---|
| 5 | Plan → #1 → **Clear this item…** → type `Confirmed and completed` → **Clear item** | Message: "Cleared. In Calendar the title now starts with “COMPLETED”…". #1 shows "cleared" in the Plan list |
| 5a | Open Apple **Calendar** → 9 Jan 2027 → #1 | Title starts `COMPLETED – Check open campus entry pass…`; notes end with `Completed in Nudge on 2026-11-02` (or the day you test) |
| 5b | Back in Nudge: gear → Tsuji plan → **Calendar ID check** → **Copy report** → paste to Claude | Claude checks #1's alarms. Expected: "none on the event" (if Calendar shows one, it re-added a default alert — report it) |
| 5c | Force-quit Nudge (swipe it away), reopen → Plan | #1 still "cleared" |
| 6 | In **Calendar**, edit #1's title: delete `COMPLETED – ` (keep the rest exactly) → Done. Then open **Nudge** | #1 is open again in the Plan list ("in N days") |
| 6a | Calendar → #1 | Notes now also end with `Reopened in Nudge on …`; alerts are back |
| 6b | Nudge → **Calendar ID check** → **Copy report** → paste to Claude | Claude checks #1: title matches the spec again; alarms include 7 days before 09:00 (−572400 s) and on the day 09:00 (+32400 s) |
| 6c | Open Nudge on the **Mac** → Plan | #1 is open on the Mac too |
| 7 | In Calendar, move #1 to **10 Jan 2027**, open Nudge → Plan; then move it back to **9 Jan**, check again | The Plan list shows 10 Jan, then 9 Jan |

Pass rule for Test 6 (agreed 1 Nov): the two real alerts come back. The device-default alert may
differ from before — that's expected. #1 ends with two extra note lines; that's expected too.

**If anything goes wrong:** don't try to fix the event by hand in a hurry. Paste the Calendar ID
check report to Claude. Worst case, the Mac export restores the calendar.

## After step 3 passes

Cleanup (agreed): remove Test mode, the Test tools screen, the test entries and the step 2
dry-run code paths. Decide whether the Calendar ID check stays as a read-only diagnostic.
