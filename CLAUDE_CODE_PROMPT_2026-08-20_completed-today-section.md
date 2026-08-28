# Claude Code prompt — commit & push "Completed Today" section

## Context
Cowork (this session's sibling) edited `ios/Nudge/Nudge/ContentView.swift` directly on
Noah's Mac at `/Users/noahflouty/Claude/nudge`. Cowork cannot commit/push to this repo's
`.git` (known limitation — see project memory `nudge-git-commit-limitation.md`), so that
part is your job.

## What changed (already done, just needs commit+push)
In `ios/Nudge/Nudge/ContentView.swift`:

1. Added a collapsible **"Completed Today"** section at the bottom of the Today tab
   (`todayTab`). Shows reminders completed today (by `completedAt`, any original due
   date — matches the existing `todayStats` "done" definition). Collapsed by default.
   Tapping a row's checkmark restores (uncompletes) it, same as `CompletedHistoryView`.
2. Repointed the Home tab's "Done today" stat card: it now switches to the Today tab
   and auto-expands the new section, instead of opening the full all-time
   `CompletedHistoryView` sheet. The Lists tab's separate "Completed" row still opens
   the full all-time history — unchanged.
3. Seeded `@State private var collapsed` with `["completed-today"]` so the new section
   starts collapsed on first render (the existing `collapsed: Set<String>` pattern
   treats *absence* from the set as expanded, so this was necessary for correct
   default state).

Note: `ios/Nudge/Nudge/TodayView.swift` is dead code (never instantiated anywhere in
the app — confirmed via `grep -rn "TodayView(" ios/`). It was intentionally left
untouched. Don't be confused by it; the real Today tab lives in `ContentView.swift`'s
`todayTab`.

## Your tasks

1. `cd` into the repo, confirm the diff matches the description above
   (`git diff ios/Nudge/Nudge/ContentView.swift`).
2. Build the iOS target (or at least typecheck) to confirm it compiles — this was
   hand-edited outside Xcode, so verify before committing:
   - New symbols added: `completedTodayReminders`, `completedTodaySection`,
     `completedTodayRow(_:)`.
   - Check `Theme.sage`, `Theme.accent`, `Theme.textMeta`, `Theme.surface`,
     `Theme.surfaceAlt`, `Theme.cardStroke`, `Theme.radius(_:)`, `Theme.minimal`,
     `Theme.spring` all resolve as used (they're copied 1:1 from existing usages in
     the same file, so should be fine, but verify).
   - Check `store.completedReminders()`, `store.toggleComplete(_:)`,
     `store.list(for:)`, `displayTitle(_:)`, `parseDate(_:)` all resolve — these are
     existing helpers used elsewhere in `ContentView.swift` / `NudgeStore.swift`.
3. If the build is clean, commit with a message like:
   `Add Completed Today section to Today tab; repoint Home "Done today" card to it`
4. Push to the remote.
5. **After committing and pushing, remove any git locks or stale locks** (e.g.
   `.git/index.lock` if present, or run `git gc` if there's lock cruft) so the repo is
   clean and smooth for the next session.
6. If the build fails, do NOT force a commit — report the compile error back instead
   so it can be fixed first.

## Safety
No secrets, keys, or credentials are touched by this change. Standard commit/push only.
