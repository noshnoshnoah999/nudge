# Claude Code prompt — 2026-11-20b: Breakfast buy reminders (step 1) — build, reinstall, push

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

`main` is pushed at `56f751c`. Committed locally, NOT pushed:
- `d437857` Breakfast buy reminders (step 1) — new `BreakfastReminders.swift`,
  `BreakfastPlannerView.swift`; changes in `BreakfastSync.swift`, `BreakfastView.swift`,
  `Models.swift` (new optional `Reminder.breakfast`), `NudgeStore.toggleComplete` (2 lines),
  `Notifications.swift` (new `NUDGE_BREAKFAST` category with "✓ Bought"), `ContentView.swift`.
- one docs commit (this prompt).

Never compiled (written without Xcode). New files are in `Nudge/` (synchronized group — no
pbxproj edit needed).

## Task

1. Run `./reinstall_nudge.sh`. Report the real result for BOTH iPhone and Mac (check the actual
   install output; it has reported false success before).
2. **If the build fails:** fix **compile errors only**, and only in the Breakfast files listed
   above (or the Breakfast lines in the others). Minimal, no behaviour change. Commit as
   `Breakfast reminders: compile fixes`, rebuild, show Noah the diff. Anything else → stop and
   report the exact error.
3. `git push` to `main`.
4. Tell Noah what to test (Home → Breakfast card):
   - Top-left **Remind me** (bell) → planner. "Everything unbought", set a time ~2 min ahead,
     Once → Save. The sheet's REMINDERS section shows it ("Breakfast: N things to buy").
     A new **Breakfast** list exists in Lists.
   - When the notification arrives: no shop name; long-press / pull it down → **✓ Bought**.
     Open the Breakfast sheet → those items are ticked with today's day; Budget shows them
     after it's opened. (Undo: untick the reminder in Lists → Breakfast — the same units untick.)
   - Long-press one unbought item → **Remind me to buy this** → planner with that item at 1.
     Title preview "Buy: Single Lemon" (×2 when 2).
   - Pick items + **Every week** → saved with a repeat.
   - Tick the planned item(s) in the Breakfast list → within a refresh the reminder completes
     itself (and a weekly one moves to next week).
   - NOT in this step: completing it from the **widget** doesn't tick items yet (step 2).

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log origin/main --oneline -3
```
