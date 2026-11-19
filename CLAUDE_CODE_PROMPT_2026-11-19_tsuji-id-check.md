# Claude Code prompt — 2026-11-19: Tsuji Calendar ID check fix — reinstall, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log --oneline -3
```

**Do NOT edit, add or commit anything, and do NOT run `git checkout`, `git restore`, `git stash`,
`git clean` or `git reset`.** The work is already committed.

## State of play

`main` was pushed at `214257d`. Committed locally, NOT pushed:

- `57c029a` Tsuji Calendar ID check: renamed/moved events no longer FAIL (one file:
  `ios/Nudge/Nudge/TsujiIDCheckView.swift`, read-only diagnostic screen)
- one docs commit with this prompt

## Task

1. Run `./reinstall_nudge.sh`. Report its real result for BOTH the iPhone and the Mac (check the
   actual install output; it has reported false success before).
2. If the build fails, **stop and report the error** — do not fix it.
3. `git push` to `main`.
4. Tell Noah: open Nudge → gear → Tsuji plan → Calendar ID check. It should say PASS, with #9's
   title marked "changed".

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log origin/main --oneline -3
```
