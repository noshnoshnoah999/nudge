# Claude Code Prompt — Build, Commit & Push: Multi-Select Bulk Move

Read `SESSION_HANDOFF_2026-07-15_multi-select-move.md` first for full context on what
changed and why.

## Your job

1. **Remove any stale git lock first** (Cowork sandbox couldn't release it):
   ```
   rm -f .git/index.lock
   ```

2. **Build the iOS app** (Xcode project under `ios/Nudge/`) and fix any compile errors.
   I reviewed the diff manually without a Swift toolchain, so treat this as an unverified
   patch — read the actual diffs in `ContentView.swift`, `ReminderCardView.swift`,
   `GroupCardView.swift`, and the new `BulkMoveView.swift` before assuming it's correct.
   One bug was already caught and fixed in review (a ternary with Void-returning calls
   in `ReminderCardView.swift`'s `.onTapGesture`) — double check there aren't others like
   it, since I couldn't compile locally.

3. **Manually sanity-check the feature** if you have simulator access: enter select mode
   from Today, select 2-3 reminders, try "keep own times" and "one time for all", try
   overriding one reminder's date independently, confirm the calendar-conflict alert
   fires when expected, confirm Cancel and tab-switching both clear selection.

4. **Commit only today's multi-select work** as its own commit — don't bundle in the
   other pending files you'll see in `git status` (there are several older uncommitted
   features/handoffs from previous sessions, per project memory). Suggested scope:
   ```
   git add ios/Nudge/Nudge/ContentView.swift \
           ios/Nudge/Nudge/ReminderCardView.swift \
           ios/Nudge/Nudge/GroupCardView.swift \
           ios/Nudge/Nudge/BulkMoveView.swift \
           SESSION_HANDOFF_2026-07-15_multi-select-move.md \
           CLAUDE_CODE_PROMPT_2026-07-15_multi-select-move.md
   git commit -m "Add multi-select bulk move for Today/Overdue reminders"
   ```

5. **Push to the remote.**

6. **After pushing, remove any lingering/stale git locks again** so the repo is clean
   for the next session:
   ```
   rm -f .git/index.lock
   ```

## Safety note
No secrets, API keys, or credentials are touched by this change. This is UI-only plus
a loop over the existing `store.reschedule()` function — no new persistence, network,
or auth code paths.

## Do not
- Do not bundle the older pending files (bold-text follow-ups, AI grouping fix, inline
  day schedule, splash sequencing, scan OCR/keychain) into this commit unless Noah has
  separately asked you to. Flag their existence to him instead if you notice them.
