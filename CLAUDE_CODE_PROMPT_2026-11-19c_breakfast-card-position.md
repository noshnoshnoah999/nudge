# Claude Code prompt — 2026-11-19c: move Breakfast card on Home — reinstall, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
cd ~/Claude/nudge
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log --oneline -5
```

**Do NOT edit, add or commit anything, and do NOT run `git checkout`, `git restore`, `git stash`,
`git clean` or `git reset`.** The work is already committed. Never print any key; never add
`Secrets.swift`.

## State of play

`main` is pushed at `ca1bff0`. Committed locally, NOT pushed:
- one commit in `ContentView.dashboardTab`: the `BreakfastHomeCard` line moved from above the stat
  grid to directly under the Next up / Still due card (above Pay day and Pinned). No other change.
- one docs commit (this prompt).

## Task

1. Run `./reinstall_nudge.sh`. Report the real result for BOTH the iPhone and the Mac (check the
   actual install output; it has reported false success before).
2. If the build fails, **stop and report the exact error** — do not fix it.
3. `git push` to `main`.
4. Tell Noah: on Home, the Breakfast card now sits right under the Still due / Next up box and
   above Pinned.

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log origin/main --oneline -3
```
