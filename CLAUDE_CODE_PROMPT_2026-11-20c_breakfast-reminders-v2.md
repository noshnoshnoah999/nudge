# Claude Code prompt — 2026-11-20c: Breakfast reminders v2 — build, reinstall, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
cd ~/Claude/nudge
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log --oneline -5
```

**Do NOT run `git checkout`, `git restore`, `git stash`, `git clean` or `git reset`.** If there are
uncommitted changes you didn't make, leave them and tell Noah. Never print any key; never add
`Secrets.swift`.

## State of play

`main` is pushed at `f44361a`. Committed locally, NOT pushed:
- `68bdd9a` Breakfast reminders v2 — `BreakfastReminders.swift`, `BreakfastPlannerView.swift`,
  `BreakfastView.swift`, `BreakfastSync.swift`, `ContentView.swift`, `Models.swift`,
  `Notifications.swift`, `NudgeStore.swift` (guard at the top of `toggleComplete`, ordering in
  `sections/todayReminders/pastDayOverdue`, weekly reset in `deleteThisOccurrence`),
  `ReminderCardView.swift`, `Shared/AppRouter.swift` (new `pendingBreakfast`).
- one docs commit (this prompt).

Never compiled (written without Xcode).

## Task

1. Run `./reinstall_nudge.sh`. Report the real result for BOTH iPhone and Mac (check the actual
   install output; it has reported false success before).
2. **If the build fails:** fix **compile errors only**, only in the files listed above, minimal,
   no behaviour change. Commit as `Breakfast reminders v2: compile fixes`, rebuild, show Noah the
   diff. Anything else → stop and report the exact error.
3. `git push` to `main`.
4. Tell Noah to run the tests in the Nudge chat's message (it lists them).

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log origin/main --oneline -3
```
