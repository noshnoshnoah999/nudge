# Claude Code prompt — 2026-11-02: Tsuji banner step 3 (Calendar saving ON) — build, install, push

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

`main` was pushed at `8c5a4b9`. On top of it, committed locally and NOT pushed:

- `12c69cb` Tsuji banner step 3: switch Calendar saving ON (approved by Noah)
- one docs commit with this prompt and `HANDOFF_2026-11-02_tsuji-banner-step3.md`

Leave exactly as they are, do not commit: `ios/Nudge/Nudge.xcodeproj/project.pbxproj` (old
one-line reorder) and the untracked `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md`.

## What changed

ONE line in `ios/Nudge/Nudge/TsujiPlan.swift`: `calendarWritesEnabled` is now **`true`** (plus
its comment). Noah approved this on 2 Nov 2026 after all step 2 tests passed and he backed up
his Tsuji Plan calendar. From this build on, clearing a Tsuji item with the typed phrase edits
that one Apple Calendar event.

## Safety rules

- This build edits Noah's real calendar when HE clears an item. **Do not run, script, automate
  or simulate a clear**, and do not open, script or automate Calendar. Noah tests himself.
- Make **no other code change** unless the build fails. If it fails, fix it with the smallest
  change and report it; do not touch `TsujiPlan.actionUIDs`, `TsujiPlan.guardFailures`,
  `TsujiStore.saveToCalendar` / `checkWritable`, or add any other EventKit write.
- Never add any other `tsuji-plan-` UID to `actionUIDs`, especially `tsuji-plan-01-…`
  (Noah's mum is invited to that event).

## Task

1. Build the iOS scheme (with NudgeWidgets) and Mac Catalyst with `xcodebuild`, as
   `reinstall_nudge.sh` does. Report any warnings in the Tsuji files.
2. Run `./reinstall_nudge.sh` and report its real result for BOTH devices (it has failed in
   provisioning-profile packaging before — check the actual install output, and confirm both the
   iPhone and Mac apps are the new build).
3. Before reporting, confirm with grep: `calendarWritesEnabled = true`, and the only `store.save(`
   in the Tsuji files is in `TsujiStore.saveToCalendar`.
4. Push to `main`.
5. Tell Noah: the step 3 test checklist is in `HANDOFF_2026-11-02_tsuji-banner-step3.md`
   ("Noah's step 3 test checklist"). Quit Nudge on the Mac before Test 5.

## Finally — clean up locks

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
rm -f .git/stale-*
git status
git log origin/main --oneline -3
```
