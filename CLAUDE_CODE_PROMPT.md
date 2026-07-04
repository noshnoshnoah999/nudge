# Claude Code — commit, push & deploy (Theme picker fix, v2.27)

## What changed (already saved to disk by Cowork)
Two files are modified in the working tree:
- `ios/Nudge/Nudge/SyncSettingsView.swift` — the Settings → Appearance → **Theme** picker was a horizontal `ScrollView`, so with 7 palettes the last ones (Graphite, **Ocean**) were clipped off the right edge. Replaced it with a `LazyVGrid` (4 columns → 4 on top, 3 below) so all 7 themes show at once without scrolling. Added `lineLimit(1)` + `minimumScaleFactor(0.8)` on the labels so longer names ("Graphite", "Lavender") don't clip.
- `ios/Nudge/Nudge/Changelog.swift` — added a v2.27 "All themes at a glance" entry.

## Steps
1. **Clear the stale lock** left by the Cowork sandbox (harmless, no git process is actually running):
   ```bash
   cd ~/Claude/nudge
   rm -f .git/index.lock
   ```
2. **Confirm the diff** is only those two files, then commit:
   ```bash
   git add ios/Nudge/Nudge/SyncSettingsView.swift ios/Nudge/Nudge/Changelog.swift
   git status -s
   git commit -m "Theme picker: show all 7 colours in a grid (Ocean no longer hidden) (v2.27)"
   ```
3. **Push:**
   ```bash
   git push
   ```
4. **Build & deploy to BOTH devices** (project convention — no need to ask):

   iPhone (`73562BAB-DA59-5AB0-A722-8AACE1D8820C`):
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates build
   APP=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-iphoneos/Nudge.app | head -1)
   xcrun devicectl device install app --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C "$APP"
   xcrun devicectl device process launch --terminate-existing \
     --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C uk.flouty.Nudge
   ```
   (Retry 2–3× if you hit `CoreDeviceError 4000`.)

   Mac (Catalyst):
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates build
   MACAPP=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-maccatalyst/Nudge.app | head -1)
   pkill -x Nudge; open "$MACAPP"
   ```
5. **Verify on device:** open Settings → Appearance → Theme and confirm all 7 swatches (Mocha, Sage, Slate, Rose, Lavender, Graphite, Ocean) are visible at once with no horizontal scroll, and tapping Ocean applies it.

## Note
This is a pure layout change (no logic, no data/blob writes, no AlarmKit), so it's low-risk. It's not compiled here — Xcode is the first real syntax check, so watch the build output.
