# Handoff — Recurring-Edit Scope Prompt ("This Event / Future Events")

Date: 2026-07-09
Author: Cowork session
Scope: Web app (`index.html`) only. No iOS change in this task.

## Goal
When the user edits **anything** on a reminder that currently has recurrence, Nudge
must ask how to apply the change before saving — mirroring Apple Calendar's
"This Event Only" / "All Future Events" prompt (see reference screenshot the user shared).

## What was built
All changes in `/Users/noahflouty/Claude/nudge/index.html`.

1. **Overlay markup** — new `#recurEditOverlay` sheet inserted after `#listOverlay`.
   Title: "How should this change be applied?" Three buttons:
   - `#recurThisOnly` — Save for This Event Only
   - `#recurFuture` — Save for Future Events
   - `#recurCancel` — Cancel

2. **`saveQA` gate** — when `ui.editingId` is set AND the existing reminder has
   `recurrence`, the computed edit is stashed in `ui.pendingRecurEdit = {id, patch}`
   and `#recurEditOverlay` is shown; the function returns before saving. The edit
   sheet (`#addOverlay`) stays open behind the prompt. Non-recurring edits and new
   reminders save exactly as before (no prompt).

3. **Three handlers** (wired in the button-binding block near `#saveListBtn`):
   - `applyRecurFuture()` — calls existing `updateReminder(id, patch)` (series-wide edit).
   - `applyRecurThisOnly()` — Apple-Calendar split:
       1. Snapshots the ORIGINAL recurrence + computes `nextOccurrence(orig)` first.
       2. `updateReminder(id, {...patch, recurrence:null})` → the edited reminder
          becomes a detached one-off carrying the user's edits.
       3. Spawns a NEW recurring reminder built directly (not via `addReminder`,
          which can't carry `interval`/`until`) with the ORIGINAL settings + original
          recurrence rule, `dueDate = nextDue`. Series continues unchanged from the
          next date.
   - `cancelRecurEdit()` — clears `ui.pendingRecurEdit`, hides only the prompt,
     leaves the edit sheet open.

## Known edge case
A recurring reminder with **no `dueDate`** has no next occurrence (`nextOccurrence`
returns null). "This Event Only" then just detaches it and the series ends — there
is nothing to roll forward. This is intentional fallback behavior, not a bug.

## Not done (deliberately)
- No in-browser test run (user asked to skip).
- No visual QA of the prompt stacking on top of the open edit sheet — eyeball this.
- iOS app not updated to match; this is web-only so far.

## Verification done
- `node --check` on the extracted `<script>` — syntax OK.
- Confirmed `ui` is a mutable object literal (safe to attach `pendingRecurEdit`).
- Confirmed no function-name collisions.

## Next steps
- Manually test both branches in the browser.
- If keeping parity, replicate the split logic on iOS (`AddReminderView.swift` /
  wherever recurring edits are saved).
