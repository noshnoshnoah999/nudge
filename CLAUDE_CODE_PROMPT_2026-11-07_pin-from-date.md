# Claude Code prompt — 2026-11-07 — "Pin from a date" for Pin to Home

Paste everything below the line into Claude Code, opened in the Nudge repo.

---

Cowork has already written this feature across the files listed below. Cowork could NOT commit (its shell can't delete files, so git would leave stale .lock files). Your job: review, build, fix compile errors only, commit, install, push. Do NOT redesign or rewrite the feature.

## SAFETY RULES (read first)
- Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset` on anything. Uncommitted work has been lost this way before.
- Stage ONLY these files for the code commit:
  - `ios/Nudge/Nudge/PinFrom.swift` (NEW — the `Nudge/` folder is a synchronized group, so no project.pbxproj edit is needed; do not touch project.pbxproj)
  - `ios/Nudge/Nudge/Models.swift`
  - `ios/Nudge/Nudge/NudgeStore.swift`
  - `ios/Nudge/Nudge/AddReminderView.swift`
  - `ios/Nudge/Nudge/RescheduleOptionsView.swift`
  - `ios/Nudge/Nudge/BulkMoveView.swift`
  - `ios/Nudge/Nudge/ReminderCardView.swift`
  - `ios/Nudge/Nudge/RemindersSync.swift`
  - `ios/Nudge/Nudge/Changelog.swift`
  - `ios/Nudge/Shared/RecurrenceEngine.swift`
  - `ios/Nudge/Shared/CompleteReminderWidgetIntent.swift`
- This prompt + `HANDOFF_2026-11-07_pin-from-date.md` go in a separate "Docs:" commit.
- Never print, log or commit any API key or secret.

## What the feature does (Noah's agreed rules)
- Edit screen: when "Pin to Home" is on, a second toggle "Pin from a date" with a date-only picker. Until that day the reminder is NOT in Home's PINNED section; from that day it is.
- Only available when the due date is tomorrow or later (greyed out with a caption otherwise). Pin day range = tomorrow…due day.
- Cards show a small "Pins 1 Dec" label (pin icon) until the day arrives.
- Moving a reminder with a pending pin day to another day asks: Keep [date] (hidden if it'd be after the new due day) / Shift by the same amount / Pick a new date. Edit screen + Reschedule sheet ask per reminder; Bulk Move asks once for the batch. Snooze / automatic move-over don't ask.
- Moved to today (or earlier): no question — alert "The 'Pin from' date won't happen anymore … straight to Pinned after you tap Done"; pin day is cleared.
- Repeating reminders: "This reminder only" vs "All future ones too" (same number of days before each due date via `pinFromGapDays`). Editing an EXISTING repeating reminder reuses the existing "This Event Only / Future Events" dialog.

## How it's built (for your review)
- `Models.swift`: `Reminder.pinFrom: String?`, `pinFromGapDays: Int?` (optional, inside the reminder JSON — no Supabase schema change; `data` is jsonb). Computed `pendingPinDay` (min of pin day and due day, nil once today or earlier) and `isPinnedNow`.
- `NudgeStore.swift`: `pinnedReminders()` filters on `isPinnedNow`. `saveReminder` / `saveReminderThisOccurrenceOnly` gain `pinFrom:` + `pinFromGapDays:` (defaulted). New `normalizedPinFrom` and `applyPinMove`. `reschedule(_:to:pin:)` gains `pin: PinMove = .keep`. Successor occurrences (toggleComplete, this-occurrence continuation, deleteThisOccurrence, advanceRoutine) roll the pin day via `RecurrenceEngine.successorPinFrom`.
- `RecurrenceEngine.swift`: `successorPinFrom(gapDays:nextDue:now:)` (nonisolated, shared with the widget).
- `CompleteReminderWidgetIntent.swift`: widget-created successors / advanced routines set `pinFrom` the same way.
- `PinFrom.swift` (new): `PinMove`, `PinMoveKind`, `Reminder.pinMoveKind(to:)`, `PendingPinMove`, `pinMoveNeeded(_:perform:)`, `PinMovePrompt` view modifier, `PinFromPickerSheet`, `pinDayLabel`.
- `AddReminderView.swift`: state + `pinFromRows` UI, `attemptSave` → `continueSave` → scope dialogs, `saveFuture()`, new `PinFromEditDialogs` modifier.
- `RescheduleOptionsView.swift`, `BulkMoveView.swift`: ask via `PinMovePrompt` before moving.
- `ReminderCardView.swift`: "Pins d MMM" meta label.
- `Changelog.swift`: new 2.33 entry.
- Not wired on purpose: TimetableView drag (same-day time change only), Smart Reschedule / move-over (only touch overdue/today items, which can never have a pending pin day). The store's normalisation keeps any other path safe.

## Steps
1. `git status` and `git diff` the files above; sanity-check against the description.
2. Build BOTH iOS and Mac Catalyst with the shared `Nudge` scheme (project uses SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor). Cowork had no compiler, so expect possible small errors (e.g. isolation/Sendable on closures, type-checker time-outs in `AddReminderView.body`). Fix ONLY real compile errors, keep behaviour identical, and tell Noah exactly what you changed and why.
3. Commit the code files: `Pin from a date: pinned reminders can wait until a chosen day (move prompts, repeat scope, card label)` — end the message with the attribution lines your environment requires.
4. Docs commit for this prompt + the handoff.
5. Install with `reinstall_nudge.sh` and confirm the REAL iPhone install result (it has reported false success before — check the actual device install output), then the Mac app.
6. `git push`.
7. Remove stale git locks (`.git/*.lock`, any `*.lock` under `.git/`) ONLY if `pgrep -fl git` shows no git process running.
8. Report: commit hashes, iOS + Mac build results, any fixes you made, install result, push result.

## Test checklist for Noah (after install)
1. New reminder due in 2+ weeks → Pin to Home on → Pin from a date on → pick a day → Save. It should NOT be in Home's Pinned; card shows "Pins <date>".
2. New reminder due today → Pin from a date is greyed out.
3. Edit that reminder, change the due date by a few days → Save asks Keep / Shift / Pick. Try each.
4. Move it earlier than its pin day → "Keep" is not offered.
5. Move it to today → "Moved to today" warning → Done → it's in Pinned on Home.
6. Reschedule sheet and Bulk Move: same question (Bulk Move asks once).
7. New repeating reminder with a pin date → asks "This reminder only / All future ones too". Complete it: this-only → next one pinned straight away; all-future → next one shows "Pins <date>" the same gap before its due date.
8. Check on the Mac too.
