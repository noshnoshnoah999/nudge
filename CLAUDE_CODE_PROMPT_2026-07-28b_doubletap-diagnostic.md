# Claude Code prompt — 2026-07-28b: DIAGNOSTIC build for the double-tap-select bug

**Copy everything below the line into Claude Code.**

---

## Your task

**This is a diagnostic build, not a fix. Do not commit it. Do not push it.**

The code is already written and sitting uncommitted in the working tree. Your job is to build it,
run one specific test on-device, and report the result.

1. Run `git status` and `git diff` to see what's there.
2. Build in Xcode and run **on an iPhone** (this bug does not reproduce on Mac Catalyst — testing on
   Mac proves nothing).
3. Run the test in "The test" below.
4. **Report the hit rate back to the user.** Commit nothing either way.
5. Then revert the two diagnostic changes (`git checkout --` the two files, or remove the two blocks
   marked `⚠ DIAGNOSTIC ONLY`) so the tree is clean for the real fix.

The only code you should write yourself is a fix for a compile error. If you hit one, fix it and say
exactly what you changed.

## Background — read this so you don't repeat dead ends

**The bug:** double-tapping a word in a reminder's title (or notes) does not reliably select it.
**iPhone only** — Mac Catalyst is fine. The failure is **intermittent and uncorrelated** with title
length, with new-vs-existing reminders, and with whether the field is already focused. The user
confirmed on 2026-07-28 that it still fails on a fully focused, fully settled, motionless screen.

**Three explanations have already been tested and falsified. Do not revisit them:**

1. *Line count / new-vs-existing correlation* — the diagnosis in `TITLE_FIELD_BUG_HANDOFF.md`. Wrong;
   that file's conclusions were single flaky observations misread as rules. It carries a correction
   banner now. Read it only for the list of dead ends.
2. *The app's own `simultaneousGesture` racing UIKit's double-tap recognizer* — fixed in commit
   `d2cd909` by moving tap-to-focus behind the field via `.background(...)`. Made no difference. That
   commit is still in place; it's harmless and arguably cleaner, but it did not fix the bug.
3. *Keyboard-avoidance scroll displacement moving the text between taps* — ruled out by the settled
   screen test above.

Nothing in the app is stealing taps: MiniCalendar's pan recognizer sets `maximumNumberOfTouches = 0`
and only captures scroll events, and it's nowhere near the title field.

## What this build probes

Two remaining suspects, both properties of the enclosing `ScrollView`, both permanently active, both
iPhone-only. This build disables **both at once** to partition the problem space in a single build.

**Change 1 — `ios/Nudge/Nudge/NudgeApp.swift`,** new `init()`:
`UIScrollView.appearance().delaysContentTouches = false`. UIScrollView holds every touch ~150ms to
decide whether it's a scroll before forwarding it to the subview. That delay sits between the user's
two taps and can push them past UIKit's double-tap interval depending on main-thread load — which
would explain intermittency.

**Change 2 — `ios/Nudge/Nudge/AddReminderView.swift` line ~416:**
`.scrollDismissesKeyboard(.interactively)` → `.never`. `.interactively` maps to
`keyboardDismissMode = .interactive`, which requires the scroll view's pan recognizer to continuously
track touches beginning on the text field. It competes for taps the whole time the keyboard is up.

**Neither change is shippable.** `.never` removes swipe-down-to-dismiss-keyboard. Disabling
`delaysContentTouches` is global and makes buttons inside scroll views highlight instantly and feel
twitchy. Both are marked `⚠ DIAGNOSTIC ONLY` in the source.

## The test

On an **iPhone**, open an **existing** reminder (not a new one):

1. Single-tap the title text to focus it. Wait two seconds — keyboard fully up, nothing moving.
2. Double-tap a word.
3. Record whether the word highlighted.
4. Repeat **ten times**, reopening the sheet each time.

Ten reps, not five. The bug is a coin flip and five reps is not enough to distinguish "fixed" from
"got lucky." Then repeat the same ten reps on the **Notes** field.

Also do ten reps **without** the two-second wait — open an existing reminder and go straight in with a
double-tap — since that's how the user actually hits it in practice.

## Reporting — this is the whole point of the build

Report three hit rates: title-with-wait, title-without-wait, notes-with-wait. Actual numbers out of
ten, not a verdict.

- **30/30** → the ScrollView is guilty. Next step is finding a UX-acceptable version: bisect which of
  the two changes mattered, then look for a targeted fix. No rewrite needed.
- **Still intermittent anywhere** → the ScrollView is exonerated and `TextField(axis: .vertical)` on
  iPhone is the problem. The agreed next step is replacing it with a `UIViewRepresentable`-wrapped
  `UITextView` (~120-180 lines; auto-grow height, placeholder, focus binding, `lineLimit(1...8)`
  behaviour and theming all need reimplementing). **Do not start that rewrite in this session** —
  report first and let the user decide.
- **Partial improvement** → report it as partial. Do not round up to "fixed." Rounding a flaky signal
  up to a rule is precisely what caused the three failed attempts before this one.

## Housekeeping

- Commit nothing. Push nothing.
- Revert both diagnostic changes once tested.
- Note: the v2.30 `Changelog.swift` entry that briefly claimed this bug was fixed has been removed,
  since the fix it described doesn't work. `Changelog.swift` should be back at 2.29 — verify that in
  `git diff` and leave it that way.
- **At the end of the session remove any stale lock files** — `.git/index.lock` and
  `ios/Nudge/.git/index.lock` — so the next session starts clean.

No API keys, secrets or user data are involved. Nothing here touches Supabase, the Keychain, auth, or
the widget.
