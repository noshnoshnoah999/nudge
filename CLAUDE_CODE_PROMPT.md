# Claude Code — build, fix, deploy & push (Grouped box, v2.29)

Cowork wrote the code to disk but **cannot commit** (no write access to `.git`) and leaves a stale
empty `.git/index.lock`. Remove the lock, commit, build (fix any Swift errors — Cowork has no
compiler), deploy to both devices, then push.

## What changed (v2.29 — follow-up to v2.28 Group Reminders)
- `ios/Nudge/Nudge/GroupCardView.swift` — when a group is expanded, the header + member cards are
  now wrapped in a dark-orange bordered box (`RoundedRectangle`, 2pt stroke, faint orange fill) so
  grouped reminders are visually separated from the individual ones around them. Collapsed groups
  are unchanged.
- `ios/Nudge/Nudge/Changelog.swift` — v2.29 entry.

## Steps

1. **Remove the stale lock** (git is blocked until then):
   ```bash
   cd ~/Claude/nudge
   rm -f .git/index.lock
   ```

2. **Stage and commit:**
   ```bash
   git add -A
   git status -s          # expect GroupCardView.swift + Changelog.swift
   git commit -m "Group cards: dark-orange box around expanded members (v2.29)"
   ```

3. **Build for iPhone; fix any compile errors, then rebuild until green:**
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates build
   ```
   Commit any fixes: `git commit -am "Fix compile errors (v2.29)"`

4. **Install & launch on iPhone** (`73562BAB-DA59-5AB0-A722-8AACE1D8820C`; retry 2–3x on
   `CoreDeviceError 4000`):
   ```bash
   APP=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-iphoneos/Nudge.app | head -1)
   xcrun devicectl device install app --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C "$APP"
   xcrun devicectl device process launch --terminate-existing \
     --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C uk.flouty.Nudge
   ```

5. **Build & deploy Mac (Catalyst):**
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates build
   ```

6. **Push:**
   ```bash
   cd ~/Claude/nudge && git push
   ```

7. **Remove any stale locks** so next session is clean:
   ```bash
   rm -f .git/index.lock ios/Nudge/.git/index.lock 2>/dev/null || true
   ```

## Test after install
Open a group on the Upcoming tab → the expanded members should sit inside a dark-orange rounded
box, clearly fenced off from the ungrouped reminders below.
