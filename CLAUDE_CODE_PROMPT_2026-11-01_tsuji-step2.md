# Claude Code prompt — 2026-11-01: Tsuji banner step 2 — build, install, push

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

`main` was pushed at `092a64e`. On top of it, committed locally and NOT pushed:

- `93864bd` Tsuji banner step 2: banner, typed clear, notifications, Test mode (Calendar saving OFF)
- one docs commit with this prompt and `HANDOFF_2026-11-01_tsuji-banner-step2.md`

Leave exactly as they are, do not commit: `ios/Nudge/Nudge.xcodeproj/project.pbxproj` (old
one-line reorder) and the untracked `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md`.

## What changed

Read `HANDOFF_2026-11-01_tsuji-banner-step2.md` (table "What step 2 adds"). New files in
`ios/Nudge/Nudge/` (synchronized group, no pbxproj edit): `TsujiStore.swift`,
`TsujiNotifications.swift`, `TsujiViews.swift`. Edited: `TsujiPlan.swift`,
`SyncSettingsView.swift`, `ContentView.swift`, `Notifications.swift`.

## Safety rules — do not break these while fixing compile errors

- `TsujiPlan.calendarWritesEnabled` must stay **`false`**. Do not change it.
- `TsujiStore.saveToCalendar` must stay the **only** `store.save(` call in Tsuji code, and it must
  keep calling `checkWritable` first. Do not add any other EventKit write (save, remove, alarm,
  title, notes, date, calendar, recurrence).
- Do not change `TsujiPlan.actionUIDs` or `TsujiPlan.guardFailures`. Never add any other
  `tsuji-plan-` UID to `actionUIDs` — especially `tsuji-plan-01-…` (Noah's mum is invited to it).
- Do not add any way to clear an item other than `TsujiClearSheet` (no swipe actions, context
  menus, notification actions).
- Do not open, script or automate Calendar. Noah tests on his devices himself.

If a compile fix would need to break any of these, stop and report instead.

## Task

1. Build the iOS scheme (with NudgeWidgets) and Mac Catalyst with `xcodebuild`, as
   `reinstall_nudge.sh` does. Fix compile errors with the smallest change, only in the seven files
   above, as a separate commit. The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`;
   `TsujiStore` is `@MainActor`, `TsujiNotifications` is a `@MainActor enum`.
   Also report any **warnings** in the Tsuji files.
2. Run `./reinstall_nudge.sh` and report its real result for BOTH devices (it has reported false
   success before — check the actual install output, and confirm the iPhone app is the new build).
3. Push to `main`.
4. Tell Noah: the step 2 test checklist is in `HANDOFF_2026-11-01_tsuji-banner-step2.md`
   ("Noah's step 2 test checklist"). Test mode is in Nudge → Settings → Tsuji plan.

## Finally — clean up locks

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
rm -f .git/stale-*
git status
git log origin/main --oneline -3
```
