# Session Handoff — Multi-Select Bulk Move (2026-07-15)

## What was built

Multi-select mode on the Today and Overdue tabs, letting Noah select several reminders
at once and move them all to new day(s)/time(s) in one action.

### Entry point
- New icon in the header row (`ContentView.swift`, `header` var), placed immediately
  next to the existing checklist/Triage icon. Only visible when `tab == 1` (Today) or
  `tab == 2` (Overdue). Icon toggles between `checkmark.circle` (off) and
  `checkmark.circle.fill` (on) to show select-mode state.

### Select mode behavior
- `ReminderCardView` gained three new (defaulted) params: `selectMode`, `isSelected`,
  `onToggleSelect`. When `selectMode` is true:
  - The leading complete-toggle circle becomes a selection circle instead.
  - Tapping anywhere on the card body toggles selection instead of opening the edit sheet.
  - The long-press context menu (Complete/Snooze/Reschedule/Edit/Delete) is suppressed,
    so bulk selection can't be interrupted by a fat-fingered destructive action.
  - Selected cards get an accent-colored border.
- `GroupCardView` (the AI-grouped folder cards) passes selection state through to its
  expanded members only. **Collapsed groups are not selectable as a unit** — this was a
  deliberate scope decision confirmed with Noah, to avoid inventing "select whole group"
  semantics (mixed times within a group, etc). Expand the group first, then select
  individual reminders inside it.
- Switching tabs (via the bottom tab bar or any internal `switchTab` call) automatically
  clears selection if leaving Today/Overdue, so a stale selection can't silently apply
  to the wrong tab's reminders.

### Bottom action bar
- New `selectionBar` view in `ContentView.swift`, shown (as a bottom overlay, same slot
  as the delete-undo toast) whenever `selectMode && !selectedIds.isEmpty`.
- Shows "N selected", a Cancel button (clears selection + exits select mode), and a
  Move button (opens the bulk-move sheet).

### Bulk move sheet — `BulkMoveView.swift` (new file)
- Takes the selected `Reminder`s as input.
- "Move all to" date picker sets a shared target date for every reminder that hasn't
  been individually overridden.
- Per-reminder rows below let Noah drag any specific reminder to a *different* day than
  the shared one — this was an explicit requirement ("some reminders to next day, some
  to a later date, let me choose"). Overriding a row's date marks it "touched" so the
  shared-date picker won't clobber it if changed again afterward.
- Toggle: **"Set one time for all"**
  - Off (default): each reminder keeps its own original time-of-day; only the date
    changes.
  - On: a single shared time picker appears, and every reminder moves to that time on
    its (possibly individually-picked) date.
- On confirm, checks each computed final date against `CalendarService` for calendar
  conflicts; if any exist, shows a confirm-anyway alert before applying.
- Applies changes via the existing `store.reschedule(id, to: Date)` — no new store
  logic was needed; this function already sets `dueDate`, `hasTime = true`, clears
  `snoozedUntil`/`tz`, and bumps `updatedAt`.

## Files changed
- `ios/Nudge/Nudge/ContentView.swift` — select-mode state, header icon, selection bar,
  bulk-move sheet wiring, `switchTab` now clears selection, `groupedRows` passes
  selection props through.
- `ios/Nudge/Nudge/ReminderCardView.swift` — selection UI + tap/long-press behavior.
- `ios/Nudge/Nudge/GroupCardView.swift` — passthrough of selection props to expanded
  members only.
- `ios/Nudge/Nudge/BulkMoveView.swift` — **new file**, the bulk-move sheet.

## Verification done in Cowork
- Manually reviewed every diff line-by-line (no Swift toolchain available in the Cowork
  sandbox to actually compile).
- Caught and fixed one real bug during review: `.onTapGesture { selectMode ? onToggleSelect() : onEdit() }`
  does not compile in Swift (ternary requires both branches to be value-producing
  expressions; these are `Void`-returning function calls). Fixed to a proper
  `if/else` block.
- Confirmed brace/paren balance across all 4 touched/new files.
- Confirmed every other existing call site of `ReminderCardView(...)` and
  `GroupCardView(...)` (in Lists, Search, Smart Collections, Home dashboard, TodayView)
  still compiles unchanged, since the new params are all defaulted and `onEdit` is
  still usable as a trailing closure.
- Confirmed `Theme.surfaceAlt`, `Theme.textMeta`, `Theme.hairline`, `Theme.textMain`,
  `Theme.spring`, `Theme.accent`, `Theme.bg`, `PressableStyle`, and
  `CalendarService.shared.conflictDescription(at:)` all exist with the signatures used.
- **Not done** (needs Xcode): an actual build, and a manual run-through on device/
  simulator to confirm the interaction feels right (tap targets, animation timing,
  whether "each reminder keeps its own time" reads clearly in the sheet).

## Known follow-ups / things to watch
- No group-level select-all — see scope decision above. If this turns out to be
  annoying in practice, it's a small addition (a checkbox on `GroupCardView.header`
  that selects/deselects every member).
- The bulk-move sheet's per-reminder DatePicker is date-only (`.compact` style); it
  intentionally does NOT let you set a per-reminder time — only the shared "set one
  time for all" toggle sets time. If Noah wants true per-reminder time overrides too,
  that's a bigger addition to `BulkMoveView`.
- Undated reminders (no `dueDate`) in a selection default to 9am when "keep own time"
  is on, since there's no original time to preserve. Worth flagging to Noah if he
  bulk-moves undated reminders and 9am isn't the desired default.

## Outstanding from previous sessions (not touched today, still pending Claude Code)
Per memory, these still need Claude Code build+commit+push from earlier sessions:
- AI grouping prompt fix (`AIGrouper.swift`, Jul 12)
- Inline day schedule (`AddReminderView.swift`, Jul 12)
- Splash + Face ID sequencing (Jul 12)
- Scan OCR + Keychain migration (2 commits, Jul 12)
- Time-conflict panel (committed 590e8af already per git log — confirm it actually
  landed; `git log` shows it as the current HEAD, so this one may already be done)

Recommend Claude Code commits today's multi-select work as its own commit, separate
from any older pending work, so they're each independently revertable.
