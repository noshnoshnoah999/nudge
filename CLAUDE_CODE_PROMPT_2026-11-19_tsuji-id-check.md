# Claude Code prompt — 2026-11-19: Tsuji ID check fix + Home error banner — reinstall, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log --oneline -5
```

**Do NOT edit, add or commit anything, and do NOT run `git checkout`, `git restore`, `git stash`,
`git clean` or `git reset`.** The work is already committed.

## State of play

`main` was pushed at `214257d`. Committed locally, NOT pushed:

- `57c029a` Tsuji Calendar ID check: renamed/moved events no longer FAIL
- `0240f1f` Docs (first version of this prompt)
- the Home error banner commit (`TsujiCheckErrorBanner` in `TsujiViews.swift`; shared
  `TsujiIDCheck.shared`, run from `TsujiStore.finish()`; banner added at the top of Home in
  `ContentView.dashboardTab`)
- one docs commit updating this prompt

All of it is read-only towards Calendar.

## Task

1. Run `./reinstall_nudge.sh`. Report its real result for BOTH the iPhone and the Mac (check the
   actual install output; it has reported false success before).
2. If the build fails, **stop and report the exact error** — do not fix it.
3. `git push` to `main`.
4. Tell Noah:
   - Nudge → gear → Tsuji plan → Calendar ID check should say PASS, with #9's title "changed".
   - Home should show NO Tsuji error banner (everything currently passes).

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log origin/main --oneline -3
```
