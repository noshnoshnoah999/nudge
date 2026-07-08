# Claude Code — build, fix, deploy & push (Fix double-tap word select, v2.30)

Cowork wrote the code to disk but **cannot commit** (no write access to `.git`) and leaves a stale
empty `.git/index.lock`. Remove the lock, commit, build (fix any Swift errors — Cowork has no
compiler), deploy to both devices, then push.

## Background — two iterations happened in this session, this describes the FINAL state

**Iteration 1:** the title and notes `TextField`s each had a
`simultaneousGesture(TapGesture().onEnded { ... })` that force-set focus on *every* tap, including
taps on an already-focused field. This was gated to only fire `if !fieldFocused`.

**Iteration 2 (user re-tested, reported "works on some reminders, not all" — specifically fails
when the title wraps to 2+ lines):** the gating alone didn't fully fix it. The
`simultaneousGesture` was still interfering with double-tap-to-select on multi-line titles even
when gated. So for the **title field only**, the `simultaneousGesture` has been **removed
entirely** — it now relies solely on `.focused($titleFocused)`. The **notes field** still has the
gated version from iteration 1 (user hadn't reported it as broken there, so it was left alone).

## What changed (v2.30 — final diff to commit)
- `ios/Nudge/Nudge/AddReminderView.swift`:
  - **Title field**: `simultaneousGesture(TapGesture()...)` removed entirely. Focus now relies only
    on `.focused($titleFocused)`.
  - **Notes field**: `simultaneousGesture(TapGesture().onEnded { if !notesFocused { notesFocused = true } })`
    kept (gated version, unchanged from iteration 1).
- `ios/Nudge/Nudge/Changelog.swift` — v2.30 entry, updated to describe the multi-line title fix.

## ⚠️ Known risk to watch for — read this before testing

The original reason the tap-forcing hack existed at all (per a code comment that was already in
the file): *"a vertical-axis TextField inside a ScrollView won't become first responder on iOS (no
keyboard on tap), though it works on Mac Catalyst."* Removing the gesture from the title field
risks bringing that original bug back — i.e. tapping into the title (especially a **new, empty**
reminder, before the 0.45s auto-focus timer at the bottom of `load()` fires) might stop reliably
raising the keyboard.

**Please explicitly test this regression, not just the fix:**
1. New reminder → tap the title field immediately (before the keyboard auto-appears) → does the
   keyboard still come up reliably?
2. Existing reminder with a **long title that wraps to 2+ lines** → tap into the title, then
   double-tap a word on the second line → does it select?
3. Existing reminder with a **short single-line title** → same double-tap test → still works?
4. Notes field, any reminder → confirm double-tap-to-select still works there (unchanged code, but
   verify nothing else broke).

If (1) regresses, do NOT just re-add the old unconditional `simultaneousGesture` blind — that's the
exact thing that caused this bug. Instead flag it back rather than guessing at a third patch.

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
   git commit -m "Fix double-tap word selection on multi-line reminder titles (v2.30)"
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

## Test after install (see the ⚠️ section above for full detail)
1. New reminder → title keyboard still pops up reliably on tap.
2. Existing reminder, long wrapping title → double-tap a word on line 2+ → selects.
3. Existing reminder, short title → double-tap → still selects.
4. Notes field → double-tap → still selects.

Report back which of these pass/fail — do not guess at further fixes without that feedback.
