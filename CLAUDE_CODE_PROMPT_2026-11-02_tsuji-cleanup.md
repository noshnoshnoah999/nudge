# Claude Code prompt — 2026-11-02: Tsuji banner cleanup — build, install, push

Repo: `~/Claude/nudge`, branch `main`.

## Before anything

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
rm -f .git/stale-*
git status
git log --oneline -4
```

**Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset` on tracked
files.** If the tree has changes other than those listed below, stop and report.

## State of play

`main` was pushed at `5e9249a`. On top of it, committed locally and NOT pushed:

- `9bad9d9` Tsuji banner cleanup: remove Test mode after all tests passed
- one docs commit with this prompt and `HANDOFF_2026-11-02_tsuji-banner-cleanup.md`

Leave exactly as they are, do not commit: `ios/Nudge/Nudge.xcodeproj/project.pbxproj` (old
one-line reorder) and the untracked `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md`.

## What changed

Test mode was removed from `TsujiStore.swift`, `TsujiNotifications.swift`, `TsujiViews.swift` and
`SyncSettingsView.swift` (the `TsujiTestToolsView` struct is gone); `TsujiPlan.swift` only had a
comment change. Mostly deletions.

## Safety rules

- `TsujiPlan.calendarWritesEnabled` stays **`true`**. Do not change it.
- `TsujiStore.saveToCalendar` must stay the only `store.save(` in the Tsuji files and keep calling
  `checkWritable` first. Do not change `TsujiPlan.actionUIDs` or `TsujiPlan.guardFailures`.
- Do not run, script or simulate a clear, and do not open, script or automate Calendar.

## Task

1. Build the iOS scheme (with NudgeWidgets) and Mac Catalyst with `xcodebuild`, as
   `reinstall_nudge.sh` does. If a removed symbol is still referenced somewhere, fix it with the
   smallest change (remove the leftover reference), as a separate commit. Report any warnings in
   the Tsuji files.
2. Run `./reinstall_nudge.sh` and report its real result for BOTH devices (confirm both apps are
   the new build).
3. Confirm with grep: `calendarWritesEnabled = true`; the only `store.save(` in the Tsuji files is
   in `TsujiStore.saveToCalendar`; no `testMode` / `TsujiTestToolsView` left.
4. Push to `main`.
5. Tell Noah: Settings → Tsuji plan should now show only **Plan** and **Calendar ID check**.

## Finally — clean up locks

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
rm -f .git/stale-*
git status
git log origin/main --oneline -3
```
