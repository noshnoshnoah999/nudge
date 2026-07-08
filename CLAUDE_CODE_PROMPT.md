# Claude Code — build, fix, deploy & push (Fix double-tap word select, v2.30)

Cowork wrote the code to disk but **cannot commit** (no write access to `.git`) and leaves a stale
empty `.git/index.lock`. Remove the lock, commit, build (fix any Swift errors — Cowork has no
compiler), deploy to both devices, then push.

## What changed (v2.30 — bug fix)
- `ios/Nudge/Nudge/AddReminderView.swift` — the title and notes `TextField`s each had a
  `simultaneousGesture(TapGesture().onEnded { ... })` that force-set focus on **every** tap,
  including taps on an already-focused field. On iPhone this raced against the system's built-in
  double-tap-to-select gesture and broke word selection specifically when editing an *existing*
  reminder (new reminders auto-focus the title 0.45s after the view opens, so this collision never
  had a chance to trigger there — which is why the bug never showed up for new reminders, and never
  showed up on Mac Catalyst either). Both gestures are now gated with `if !titleFocused` /
  `if !notesFocused` so they only fire on the tap that establishes focus, not on every subsequent tap.
- `ios/Nudge/Nudge/Changelog.swift` — v2.30 entry.

**Not verified on-device** — Cowork can't build/run the iOS app. Please confirm after install:
open an *existing* reminder, tap into the title (or notes) where there's already text, then
double-tap a word — it should highlight the word like it does for a brand-new reminder.

## Steps

1. **Remove the stale lock** (git is blocked until then):
   ```bash
   cd ~/Claude/nudge
   rm -f .git/index.lock
   ```

2. **Stage and commit:**
   ```bash
   git add -A
   git status -s          # expect AddReminderView.swift + Changelog.swift
   git commit -m "Fix double-tap word selection when editing existing reminders (v2.30)"
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

## Test after install
On iPhone: open an existing reminder (not a new one), tap into the title where there's already
text, then double-tap a word — it should select/highlight, same as it already does for new
reminders and on Mac. Also sanity-check that tapping into an existing reminder's title/notes still
focuses and shows the keyboard normally (the gating shouldn't have broken that).
