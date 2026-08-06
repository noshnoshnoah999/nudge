# Prompt for Claude Code — 2026-08-06

Copy everything below the line into Claude Code, run from the repo root.

---

Read `HANDOFF_2026-08-06_widget-today-vs-pastday.md` first for full context.

**IMPORTANT — do NOT run `git checkout`, `git restore`, `git stash`, or `git clean` at any
point in this session.** There are uncommitted changes in the working tree that were written
in Cowork and exist nowhere else. A previous session destroyed work this way. If a git
command complains about the working tree, stop and tell me rather than cleaning it.

## Context

`ios/Nudge/NudgeWidgets/NudgeWidgets.swift` was edited in Cowork. The Today widget was
listing overdue reminders from previous calendar days; it should show only what's due today.
The app already had this rule (`NudgeStore.pastDayOverdue()`); the widget diverged. Also
fixed: `isOver` ignored `hasTime`, so date-only reminders read as overdue from 00:01 on their
own due date.

## Tasks

1. There is a **stale `.git/index.lock`**. Remove it before doing anything else:
   `rm -f .git/index.lock`

2. `git status` and `git diff` — confirm the only modified tracked file is
   `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`, and that the Cowork edits are present
   (look for `pastDayItems`, `showingOverdue`, and `wNextRefresh`). If those symbols are
   missing, STOP and tell me — the edits were lost.

3. **Build the widget extension** for iOS. Use the shared `Nudge.xcscheme`. Note the project
   builds with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` and targets iOS 26.5. Fix any
   compile errors. Two things I could not verify without a compiler and want you to check
   specifically:
   - `let listHeight = ...` is declared inside a `ViewBuilder` `else` branch in
     `TodayWidgetView.body`. Result builders leave declaration statements alone, so this
     should be legal, but confirm it compiles.
   - `WItem` gained `var priority: String = "normal"` as the last stored property, relied on
     to keep the existing positional memberwise initialisers in `NudgeEntry.sample` valid.
     Confirm those still compile.

4. Build the **app** target too, to be sure nothing else references the changed types.

5. Once it builds clean, commit. Suggested message:

```
Widget: show only today's reminders, not the whole overdue pile

The Today widget listed anything past its due time, so reminders from
previous days piled into it. The app has drawn this line since the
Today/Overdue tab split - NudgeStore.pastDayOverdue() keeps an item due
earlier today on the Today page and only moves it to Overdue once midnight
rolls it into a past day. build() tested `d < now` and ignored that.

- Split today's items from the past-day pile in NudgeProvider.build();
  they are never mixed.
- isOver now mirrors NudgeStore.isOverdue()'s day-end cutoff, so a
  date-only reminder is no longer overdue from 00:01 on its own due date.
- When today is completely empty the list falls back to the past-day pile
  behind an "N overdue" caption, so the widget never reads "All clear"
  while a stale pile sits in Overdue.
- The small Overdue widget now counts past-day items only, matching
  pastDayOverdueCount() and the Overdue tab.
- Timeline refresh is now min(30 minutes, next midnight), because the
  today-vs-past-day test flips at 00:00.
```

Also decide with me whether to commit the two untracked Aug 5 files
(`HANDOFF_2026-08-05_widget-recurring-completion.md`,
`CLAUDE_CODE_PROMPT_2026-08-05_widget-recurring-completion.md`) plus today's two new
markdown files in the same commit or a separate docs commit.

6. Push to origin.

7. **After committing and pushing, remove any remaining git locks or stale locks**
   (`.git/index.lock`, `.git/HEAD.lock`, `.git/refs/**/*.lock`) so the next session starts
   clean.

8. Report back: the commit hash, whether both targets built, and anything in the diff you
   think is wrong. Don't tell me it's fine if it isn't.

## Then I'll test on device

Verification checklist is in the handoff file, section "What to verify on device".
The one I most expect to break is #6 — list overflow in the fallback state at the largest
configured font, since that state adds a caption line above the rows.
