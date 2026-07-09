# Handoff — Recurring-Edit Scope Prompt ("This Event / Future Events")

Date: 2026-07-09
Author: Cowork session
Scope: Web app (`index.html`) AND iOS/macOS (SwiftUI, one Catalyst codebase).

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

---

## iOS / macOS (added same day)

One SwiftUI codebase runs iOS and Mac (Mac Catalyst — confirmed via
`!targetEnvironment(macCatalyst)` guards in `saveReminder`). No separate Mac target,
so this was built once.

### Files changed
- `ios/Nudge/Nudge/AddReminderView.swift`
- `ios/Nudge/Nudge/NudgeStore.swift`

### AddReminderView.swift
- New `@State private var showRecurScopeDialog`.
- New `.confirmationDialog("How should this change be applied?")` with three buttons:
  Save for This Event Only → `saveThisEventOnly()`, Save for Future Events → `save()`,
  Cancel.
- `attemptSave()` unchanged conflict check, but its else-branch and the conflict
  alert's "Schedule anyway" now call new `afterConflict()`.
- `afterConflict()`: if `editing != nil && editing.recurrence != nil` → show scope
  dialog; else `save()`. **Order per user: calendar-conflict alert FIRST, then scope.**
- `saveThisEventOnly()`: mirrors `save()` but routes to the new store method.

### NudgeStore.swift
- New `saveReminderThisOccurrenceOnly(...)` (same signature shape as `saveReminder`):
  1. Snapshots the ORIGINAL reminder + computes `nextOccurrence(after:rec:)` first.
  2. Calls existing `saveReminder(..., recurrence: nil, ...)` → edited reminder becomes
     a one-off with the user's edits.
  3. Copies the ORIGINAL struct value (`var cont = orig`, preserving every field —
     prep links, groups, alerts, tz) and overrides id/dueDate/timestamps/completion,
     re-setting `recurrence = origRec`. Inserts it → series continues from next date.
  4. No next date (no dueDate / past `until`) → series ends, nothing inserted.
  - Non-recurring fallback: delegates to plain `saveReminder`.

### Design note
The continuation copies `groupId`/`groupTitle`, so if the original was in a group the
next occurrence rejoins that group card. Intended (same logical series) — flag if not.

### NOT done / verify
- **No Swift build run** — the Cowork sandbox is Linux with no Swift toolchain. Must be
  compiled/tested in Xcode on the Mac. Watch for: the memberwise-copy approach relies on
  `Reminder` being a value type (it is, a struct); `iso()` / `nextOccurrence` are on the
  same `NudgeStore` class (accessible).
- Test both branches on device: edit a recurring reminder → conflict prompt (if clashing)
  → scope prompt → verify This Event detaches + series continues, Future edits the series.
