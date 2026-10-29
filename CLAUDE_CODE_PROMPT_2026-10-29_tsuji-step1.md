# Claude Code prompt — 2026-10-29: Tsuji banner step 1 (read-only Test 0) — build, install, push

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

`main` was pushed at `c03f1e1`. On top of it, committed locally and NOT pushed:

- `71ab05b` Tsuji banner step 1: read-only Test 0 calendar ID check
- one docs commit with this prompt

Leave exactly as they are, do not commit: `ios/Nudge/Nudge.xcodeproj/project.pbxproj` (old
one-line reorder) and the untracked `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md`.

## What changed

Spec: `TSUJI_ACTION_BANNER_SPEC.md`. Noah's decisions on top of it:
`HANDOFF_2026-10-29_tsuji-banner.md` (that file wins where they differ).

- `ios/Nudge/Nudge/TsujiPlan.swift` (new) — the 13 Tsuji action-event UIDs, one constant.
- `ios/Nudge/Nudge/TsujiIDCheckView.swift` (new) — read-only "Test 0" screen: lists every event
  in the "Tsuji Plan" calendar with its `calendarItemExternalIdentifier`, compares the 13 to the
  spec, checks UID 01 reports invitees, and offers "Copy report".
- `ios/Nudge/Nudge/SyncSettingsView.swift` — new "Tsuji plan" section (after "Overdue") with a
  link to the check.

`Nudge/` is a synchronized folder group: no pbxproj edit needed.

## Safety — this step is READ-ONLY

- Do **not** add any EventKit write: no `save`, `remove`, `commit`, alarm, title or notes
  changes. If a compile fix seems to need one, stop and report.
- Do **not** change `TsujiPlan.actionUIDs`. Never add any other `tsuji-plan-` UID, especially
  `tsuji-plan-01-…` (Noah's mum is invited to that event).
- Do not open, script or automate Calendar. Noah runs the check himself.

## Task

1. Build the iOS scheme (with NudgeWidgets) and Mac Catalyst with `xcodebuild`, as
   `reinstall_nudge.sh` does. Fix compile errors with the smallest change, only in the three
   files above, as a separate commit. (The project builds with
   `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`; the new `TsujiIDCheck` class is `@MainActor`.)
2. Run `./reinstall_nudge.sh` and report its real result for BOTH devices (it has reported
   false success before — check the actual install output).
3. Push to `main`.
4. Tell Noah: open **Settings → Tsuji plan → Calendar ID check** on the **iPhone and the Mac**,
   tap **Copy report**, and paste both reports into the Nudge project chat.

## Finally — clean up locks

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
rm -f .git/stale-*
git status
git log origin/main --oneline -3
```
