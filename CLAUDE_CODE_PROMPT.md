# Claude Code — build, fix, deploy & push (Group reminders, v2.28)

Cowork wrote all the code to disk but **could NOT commit** — the Cowork sandbox has no write
access to `.git`, and it left a **stale empty `.git/index.lock`** it couldn't delete. So your job:
remove the lock, commit, make it compile (fix any Swift errors — Cowork has no compiler and
couldn't verify), deploy to both devices, then push.

> HEAD is still at the previous commit (`Remove daily morning digest notification`). All the new
> files and edits are present and staged/unstaged in the working tree — nothing is lost.

## What changed (feature: AI Group Reminders — native only)
New files: `AIGrouper.swift`, `GroupLog.swift`, `GroupCardView.swift`, `GroupViews.swift`.
Edited: `Models.swift`, `NudgeStore.swift`, `ContentView.swift`, `SyncSettingsView.swift`,
`BackgroundTasks.swift`, `Changelog.swift`. Full detail in `GROUP_FEATURE_HANDOFF.md`.

Summary: reminders can be bundled into collapsible "group cards" (non-destructive — sets
`groupId`/`groupTitle`/`groupSource`). Runs on demand from Settings and automatically at 23:50 with
a morning orange review banner. Only no-date / far-off reminders are candidates.

## Steps

1. **Remove the stale lock** the Cowork sandbox left behind (required — git is blocked until then):
   ```bash
   cd ~/Claude/nudge
   rm -f .git/index.lock
   ```

2. **Stage and commit** (this is the real commit — Cowork couldn't make it):
   ```bash
   git add -A
   git status -s          # expect the 8 changed + 4 new files listed in "What changed"
   git commit -m "Add AI Group Reminders feature (v2.28)"
   ```

3. **Build for iPhone and FIX ANY COMPILE ERRORS.** This is the important part — the code was
   written without a compiler. Likely spots to check if it fails: the new `ListItem` enum switch
   in `ContentView.swift` (`groupedRows`, `sectionView`), and the new `NudgeStore` methods.
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates build
   ```
   If it fails, read the error, fix the Swift, rebuild until green. Commit any fixes:
   ```bash
   git commit -am "Fix compile errors in Group Reminders feature"
   ```

4. **Install & launch on iPhone** (`73562BAB-DA59-5AB0-A722-8AACE1D8820C`). Retry 2–3x on
   `CoreDeviceError 4000`:
   ```bash
   APP=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-iphoneos/Nudge.app | head -1)
   xcrun devicectl device install app --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C "$APP"
   xcrun devicectl device process launch --terminate-existing \
     --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C uk.flouty.Nudge
   ```

5. **Build & deploy Mac (Catalyst)** — project convention is both devices:
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates build
   ```
   (Install/launch the Catalyst build the usual way.)

6. **Push:**
   ```bash
   cd ~/Claude/nudge
   git push
   ```

7. **Remove any stale locks** so the next session starts clean:
   ```bash
   rm -f .git/index.lock ios/Nudge/.git/index.lock 2>/dev/null || true
   ```

## Quick manual test after install
- Add ~4 no-date reminders on a shared theme (e.g. "email Sam", "email tutor", "buy milk",
  "buy bread"). Settings → Group reminders → "Group similar reminders now" → expect 1–2 groups.
- On the Upcoming tab they should appear as collapsible group cards; tap to expand; long-press →
  Ungroup restores them.
- Toggle "Group automatically at 23:50" off/on and confirm it persists.
