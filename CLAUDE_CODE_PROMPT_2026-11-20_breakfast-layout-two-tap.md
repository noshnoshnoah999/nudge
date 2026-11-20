# Claude Code prompt — 2026-11-20: Breakfast layout + two-tap tick — build, reinstall, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
cd ~/Claude/nudge
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log --oneline -5
```

**Do NOT run `git checkout`, `git restore`, `git stash`, `git clean` or `git reset`.** If there
are uncommitted changes you didn't make, leave them and tell Noah. Never print any key; never add
`Secrets.swift`.

## State of play

Committed locally, NOT pushed:
- `773af92` Breakfast: unbought on top, collapsed Bought list per week, two-tap tick with heartbeat
  (only `ios/Nudge/Nudge/BreakfastView.swift` changed)
- one docs commit (this prompt)

This code has **not been compiled** (written without Xcode). It uses `.phaseAnimator` (iOS 17+).

## Task

1. Run `./reinstall_nudge.sh`. Report the real result for BOTH iPhone and Mac (check the actual
   install output; it has reported false success before).
2. **If the build fails:** fix **compile errors only**, and only in `BreakfastView.swift`. Minimal
   fixes, no behaviour change. Commit as `Breakfast: compile fixes`, rebuild, show Noah the diff.
   Any other failure → stop and report the exact error.
3. `git push` to `main`.
4. Tell Noah what to test (Home → Breakfast card):
   - This week: unbought items on top, grouped by shop; a collapsed **BOUGHT (n)** row underneath.
     Tap it → bought items, newest day first, each with its day (e.g. "Thu 19").
   - Next week (expand it): same layout.
   - Tap a circle once → it fills and beats like a heartbeat, caption says "Tap again to tick".
     Wait 3 s → it stops, nothing ticked. Tap twice → ticked, moves into Bought.
   - Same two taps to untick from the Bought list.
   - Mac: same, with clicks.

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log origin/main --oneline -3
```
