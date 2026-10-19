# Claude Code prompt — 2026-10-19: iPhone launch crash fix — build, install, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log --oneline -4
```

**Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset` on tracked
files.** If the tree has changes other than those listed below, stop and report.

## State of play

`main` was pushed at `541d989`. On top of it, committed locally and NOT pushed:

- `39f86c7` Fix iPhone launch crash: ContentView.body overflowed the main-thread stack
- one docs commit with this prompt

Leave exactly as they are, do not commit: `ios/Nudge/Nudge.xcodeproj/project.pbxproj` (old
one-line reorder) and the untracked `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md`.

## The bug

The Debug build from `541d989` installed and ran on the Mac but crashed on the iPhone at
launch: `Thread 1: EXC_BAD_ACCESS (code=2…)` at `case 0: dashboardTab` inside
`ContentView.body` — a main-thread stack overflow (the iPhone's main-thread stack is far
smaller than the Mac's). `39f86c7` moves the tab switch into `tabContent` (one small
AnyView-returning function per tab) and moves the AI move-over banner into its own struct,
`Nudge/MoveOverBanner.swift` (new file; `Nudge/` is a synchronized group, no pbxproj edit).

## Task

1. Build the iOS scheme (with NudgeWidgets) and Mac Catalyst with `xcodebuild`, as
   `reinstall_nudge.sh` does. Fix compile errors with the smallest change, only in
   `Nudge/ContentView.swift` and `Nudge/MoveOverBanner.swift`, as a separate commit.
2. Run `./reinstall_nudge.sh` and report its real result for BOTH devices.
3. Launch Nudge on the iPhone and confirm it gets past launch to the Home tab. If it still
   crashes with EXC_BAD_ACCESS code=2 in ContentView.body, do NOT remove features: report the
   crash frame, and the next step is splitting more of ContentView.body into separate View
   structs (banners/header) the same way.
4. Push to `main`.

## Finally — clean up locks

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log origin/main --oneline -3
```
