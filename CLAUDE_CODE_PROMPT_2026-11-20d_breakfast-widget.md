# Claude Code prompt — 2026-11-20d: Breakfast reminders on the widget — build, reinstall, push

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

`main` is pushed at `119b187`. Committed locally, NOT pushed:
- `25c512b` Widget: Breakfast reminders first, tap opens the shopping list, never complete
  (`NudgeWidgets/NudgeWidgets.swift`, `NudgeWidgets/WidgetData.swift`,
  `Shared/CompleteReminderWidgetIntent.swift`, `Nudge/NudgeApp.swift`)
- one docs commit (this prompt).

Never compiled (written without Xcode). This touches the WIDGET EXTENSION target, so make sure
the reinstall rebuilds and installs the widget too.

## Task

1. Run `./reinstall_nudge.sh`. Report the real result for BOTH iPhone and Mac (check the actual
   install output; it has reported false success before).
2. **If the build fails:** fix **compile errors only**, only in the four files above, minimal,
   no behaviour change. Commit as `Breakfast widget: compile fixes`, rebuild, show Noah the diff.
   Anything else → stop and report the exact error.
3. `git push` to `main`.
4. Tell Noah what to test:
   - Have a Breakfast reminder due today. On the Today & Overdue widget it is the FIRST row.
   - Tap it once → Nudge opens on the Breakfast list with "REMINDER FOR …" grouped on top.
     No "tap again", nothing completed.
   - Other rows still need two taps to complete, as before.
   - If the widget still looks old, long-press it → Edit Widget, or remove and re-add it.

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log origin/main --oneline -3
```
