# Claude Code (use Opus) — fix title field keyboard/double-tap bug, then build, deploy & push

**Use the Opus model for this session** — this bug needs real on-device iteration in Xcode, not a
single blind patch. Two prior Cowork attempts (gesture-based, made without ability to build/run)
each fixed one symptom and broke another. Read the full history before touching anything:

**Read `TITLE_FIELD_BUG_HANDOFF.md` in the repo root first — it has the complete timeline of what
was tried, what broke, and why. Do not repeat those two iterations.**

## Quick summary
`ios/Nudge/Nudge/AddReminderView.swift` — the title `TextField` (vertical-axis, inside a
`ScrollView`) has been through two failed fixes this session:
1. Gating a tap-forcing gesture → fixed double-tap-select for single-line titles, still broken for
   multi-line/wrapped titles.
2. Removing the gesture entirely → broke keyboard-on-tap entirely for multi-line titles (regression,
   confirmed by user on-device).

Current working-tree state (uncommitted): title field has **no** tap gesture, relies only on
`.focused($titleFocused)`. This is currently broken (keyboard doesn't open for wrapped titles) —
**do not build/ship this as-is.**

## What to do
1. Read `TITLE_FIELD_BUG_HANDOFF.md` fully.
2. Check `git status` / `git diff` to see the exact uncommitted state before changing anything.
3. Reproduce all four cases on a real device/simulator before writing any fix:
   new+single-line, new+multi-line, existing+single-line, existing+multi-line — check both
   "does keyboard open on tap" and "does double-tap-select work" for each.
4. Iterate on a real fix (see the handoff doc's "Suggested directions" section — gesture-priority
   alternatives like `.onTapGesture` vs `simultaneousGesture`, or falling back to a
   `UIViewRepresentable`-wrapped `UITextView` if gesture tricks can't satisfy both requirements).
5. Update `ios/Nudge/Nudge/Changelog.swift`'s v2.30 entry to accurately describe the real fix (the
   current uncommitted entry describes iteration 1's partial fix — rewrite it once you know what
   actually works).
6. Verify all four cases pass on-device before committing.

## Steps once the fix is verified on-device

1. **Remove the stale lock** (git is blocked until then):
   ```bash
   cd ~/Claude/nudge
   rm -f .git/index.lock
   ```

2. **Stage and commit:**
   ```bash
   git add -A
   git status -s
   git commit -m "Fix title field keyboard focus + double-tap select (v2.30)"
   ```

3. **Build for iPhone; fix any compile errors, then rebuild until green:**
   ```bash
   cd ios/Nudge
   xcodebuild -project Nudge.xcodeproj -scheme Nudge \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates build
   ```
   Commit any fixes: `git commit -am "Fix compile errors (v2.30)"`

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

## Before declaring this fixed, explicitly confirm on-device
- [ ] New reminder, single-line title: keyboard opens on tap, double-tap-select works.
- [ ] New reminder, multi-line/wrapped title: keyboard opens on tap, double-tap-select works.
- [ ] Existing reminder, single-line title: keyboard opens on tap, double-tap-select works.
- [ ] Existing reminder, multi-line/wrapped title: keyboard opens on tap, double-tap-select works.
- [ ] Notes field still works as before (unaffected by title-field changes).
- [ ] Mac Catalyst: title field still focuses and edits normally.

If any of these fail, do not commit — iterate further, and update
`TITLE_FIELD_BUG_HANDOFF.md` with what was tried next if handing off again.
