# Claude Code prompt — 2026-10-18: test, build, install, push the duplicate-reminder fixes

Repo: `~/Claude/nudge`, branch `main`. Read `HANDOFF_2026-10-18_duplicates-and-sync-fixes.md` first.

## Before anything

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
git log --oneline -6
```

**Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, or `git reset` on tracked
files.** If the tree has changes other than those listed below, stop and report.

## State of play

Committed locally, NOT pushed, written without a compiler (no Swift toolchain was available):

- `708b056` Fix duplicate reminders, reverting edits/links, and completion lag
- one docs commit with the handoff and this prompt

Expected dirty / untracked — **leave all of these exactly as they are, do not commit them**:
- `ios/Nudge/Nudge.xcodeproj/project.pbxproj` — the old one-line RecurrenceEngine file-reference reorder. Noah asked for it to stay uncommitted.
- `CLAUDE_CODE_PROMPT_2026-10-09_sonnet-5-5.md` — untracked, leave it.

## Task

1. Run the sync merge tests and report the output verbatim:
   ```bash
   ./ios/Nudge/SyncMergeTests/run.sh
   ```
   It must end with `ALL PASSED`. `run.sh` now also compiles `Shared/RecurrenceEngine.swift` (it had
   been failing to compile since 2026-08-05 because Models.swift bridges to RecurrenceEngine).
2. Build the iOS app scheme (includes the NudgeWidgets extension) and Mac Catalyst with
   `xcodebuild`, the same way `reinstall_nudge.sh` builds.
3. If tests or builds fail, fix with the smallest change that keeps the intended behaviour, and
   commit as one separate commit "Fix build for 2026-10-18 duplicate fixes". Only touch:
   - `ios/Nudge/Nudge/CloudSync.swift`
   - `ios/Nudge/Nudge/NudgeStore.swift`
   - `ios/Nudge/Nudge/RemindersSync.swift`
   - `ios/Nudge/Nudge/SyncSettingsView.swift`
   - `ios/Nudge/Nudge/ReminderCardView.swift`
   - `ios/Nudge/Nudge/Notifications.swift`
   - `ios/Nudge/Nudge/Changelog.swift`
   - `ios/Nudge/Shared/CompleteReminderWidgetIntent.swift`
   - `ios/Nudge/Shared/RecurrenceEngine.swift`
   - `ios/Nudge/SyncMergeTests/main.swift`, `ios/Nudge/SyncMergeTests/run.sh`

   Most likely to need attention (project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`):
   - `SyncMeta` now has an in-memory `memo` and a `private enum CodingKeys` that excludes it.
     `SigMemo` is a new small struct. Keep `memo` OUT of the encoded cache.
   - `RecurrenceEngine` now `import CryptoKit` for `successorId(of:)`; it must still compile in
     the widget extension and stay `nonisolated`.
   - `NudgeStore.writeCache()` encodes on the main actor and writes `Data` on a private serial
     `DispatchQueue` (`cacheWriteQueue`). Only `Data` and `URL` cross into that closure.
   - `CompleteReminderWidgetIntent.swift`: `switch await rowState(...)` with `case nil / .live? /
     .absent?, .deleted?`, new `StateWrap`, and `UpsertRow` with a custom `encode(to:)`.
   - The global `markPushed(_:meta:)` in CloudSync replaced NudgeStore's private `markPushed`.

   **Hard rules:**
   - Do NOT set `RemindersSync.isAvailable` back to `true` or re-show the Apple Reminders toggle
     to make anything compile. Noah decided to switch Apple Reminders sync off; it was the
     source of the duplicates.
   - Do NOT replace `RecurrenceEngine.successorId(of:)` with a random id anywhere.
4. Run `./reinstall_nudge.sh` to install on iPhone + Mac, and report its real result (exit
   codes, not grepped text). BOTH devices must get the new build — an old build on either
   device keeps the Apple mirror running and keeps creating duplicates.
5. Push to `main`.

## Finally — clean up locks

After the commit(s) and push succeed:

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock
git status
```

Confirm `git status` shows only the untouched `project.pbxproj` change and the untracked
2026-10-09 prompt, and that the push landed (`git log origin/main --oneline -3`).
