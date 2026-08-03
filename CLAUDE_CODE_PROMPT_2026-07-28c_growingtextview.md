# Claude Code prompt — 2026-07-28c: replace title/notes TextField with GrowingTextView

**Copy everything below the line into Claude Code.**

---

## Your task

**The code is already written and sitting uncommitted in the working tree. Do not rewrite it.**
Build it, test it on-device, and ship it only if it passes.

1. `git status` / `git diff` first.
2. Build in Xcode, run **on an iPhone**. (The bug never reproduced on Mac Catalyst, so testing there
   proves nothing about the fix — but see the Catalyst regression check below, which still matters.)
3. Work through the test checklist. **The double-tap test is 10 reps, not 1.**
4. **Pass** → add a `Changelog.swift` v2.30 entry, commit, push, clear stale locks.
5. **Fail** → commit nothing, report what failed, stop.

Write code yourself only to fix a compile error. If you hit one, fix it and say exactly what changed.

## What changed and why

**New file:** `ios/Nudge/Nudge/GrowingTextView.swift` — a `UIViewRepresentable` wrapping a
`UITextView`, with placeholder label, auto-grow height, min/max line clamping and a two-way `Bool`
focus binding.

**Modified:** `ios/Nudge/Nudge/AddReminderView.swift` — the title and notes fields are now
`GrowingTextView` instead of `TextField(axis: .vertical)`. `titleFocused` and `notesFocused` changed
from `@FocusState` to plain `@State` (GrowingTextView takes a `Bool` binding, not SwiftUI focus).
Every existing `titleFocused = false` / `= true` assignment elsewhere in the file is untouched and
still works.

**Also in this diff:** the two `⚠ DIAGNOSTIC ONLY` blocks from the previous session are reverted
(`NudgeApp.swift` is back to no `init()`, `AddReminderView` is back to
`.scrollDismissesKeyboard(.interactively)`), and the false v2.30 `Changelog.swift` entry is gone.

`GrowingTextView.swift` lives in `Nudge/`, which is a `PBXFileSystemSynchronizedRootGroup` — **no
`project.pbxproj` edit is needed.** Xcode picks it up automatically. If the build says the type is
undefined, that's an Xcode cache issue, not a missing file reference.

### Why a rewrite rather than another small fix

Double-tap-to-select-a-word in the reminder title failed intermittently, **iPhone only**,
uncorrelated with title length, new-vs-existing, or focus state. Four fixes were tried and measured:

1. Gating the tap-to-focus `simultaneousGesture` on `!isFocused` — partial at best.
2. Removing that gesture entirely — regressed the keyboard not opening at all.
3. Moving tap-to-focus behind the field via `.background(...)` (commit `d2cd909`) — no change.
4. Disabling both suspect ScrollView behaviours at once (`delaysContentTouches = false` +
   `.scrollDismissesKeyboard(.never)`) — **0/10**. That exonerated the enclosing ScrollView and left
   `TextField(axis: .vertical)` itself as the cause.

`TITLE_FIELD_BUG_HANDOFF.md`'s line-count diagnosis is wrong and carries a correction banner. Don't
revisit any of the above.

**Do not swap this for `TextEditor` as a "simpler" option.** `TextEditor` is internally scrollable
and nesting it in the sheet's outer `ScrollView` creates a pan-gesture conflict. `GrowingTextView`
keeps `isScrollEnabled = false` until content exceeds `maxLines` specifically to avoid that.

## Test checklist

### 1. The actual fix — 10 reps
Existing reminder, open the sheet, go straight in with a double-tap on a word in the title. Record
hit rate out of 10. **Pass = 10/10.** Report the real number; 8/10 is a fail, not a pass. Then 5 reps
on the Notes field.

Also check: double-tap-drag to extend selection, tap-and-hold for the magnifier/caret, Select All,
and copy/paste.

### 2. Regressions — this rewrite touches far more than the bug
- Tap either field: keyboard opens. Tap the title card's **padding** rather than the text: still
  focuses.
- **New reminder auto-focus** — the title should focus by itself ~0.45s after the sheet opens
  (`load()`, line ~623).
- Placeholder text shows when empty, disappears on first character, returns when cleared.
- Title **grows** as it wraps, stops at 8 lines and then scrolls internally. Notes starts at 2 lines,
  caps at 6.
- **Caret does not jump to the end while typing mid-string.** Put the caret in the middle of an
  existing title and type — if it jumps, the `if tv.text != text` guard in `updateUIView` is failing.
- Keyboard drops when: the Scan button is tapped (line ~192), the Photos picker is tapped (~350), a
  date/time picker opens (~409).
- The live "buy" rule still fires — type "buy milk" in a new reminder's title and confirm it drops
  into Shopping with a payday date. This depends on the text binding firing `onChange`, which the
  rewrite routes through `textViewDidChange`.
- Typing in the title still triggers the "Claude - " list rule.
- Editing an existing reminder loads its title and notes correctly and saves changes.
- Font, size, colour and spacing look **the same as before** in both fields.
- Switch theme in Settings, reopen the sheet: text colour follows the new theme.
- Swipe-down-to-dismiss-keyboard still works (`.scrollDismissesKeyboard(.interactively)` is back).
- Dragging a finger across the text field still scrolls the sheet.

### 3. Mac Catalyst regression check — do not skip
Catalyst is the platform where this **already worked**, so it has the most to lose. Build and run on
Mac and confirm: both fields focus and type, double-click selects a word, auto-grow works, nothing
looks visually off.

## If it fails

Report which checklist item failed and stop. Do not start a fifth round of gesture experiments.

Most likely failure points, in order: caret jumping while typing (the text-sync guard), height
clamping fighting the outer ScrollView, and focus sync looping between `updateUIView`'s
`DispatchQueue.main.async` and the coordinator's begin/end-editing callbacks. All three are in
`GrowingTextView.swift` and are fixable — but report before changing anything.

## Housekeeping

- Commit only on a full pass, including 10/10 on the double-tap test.
- Add the v2.30 `Changelog.swift` entry as part of the passing commit, not before.
- Push once committed.
- **Remove any stale lock files at the end** — `.git/index.lock` and `ios/Nudge/.git/index.lock`.

No API keys, secrets or user data involved. Nothing touches Supabase, the Keychain, auth, or the
widget.
