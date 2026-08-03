# Claude Code prompt — 2026-07-28: double-tap-to-select race in AddReminderView

**Copy everything below the line into Claude Code.**

---

## Your task

**The code is already written and sitting uncommitted in the working tree. Do not rewrite it.**
Your job is to build it, test it on-device, and ship it if it passes.

1. Run `git status` and `git diff` to see what's there before doing anything.
2. Build in Xcode and run on-device.
3. Test using the table in "Testing" below — every case, **five times each**, record hit rates.
4. **If it passes 5/5 everywhere:** commit, push, clear stale git locks.
5. **If it fails:** commit nothing, revert nothing, report the hit rates and which failure mode you
   saw, and stop. Do not attempt another gesture-based workaround. Do not start the `UITextView`
   rewrite without asking the user first.

Only make code changes yourself if the build fails to compile — in that case fix the compile error
and say exactly what you changed and why.

## What was changed and why

**Files touched:** `ios/Nudge/Nudge/AddReminderView.swift`, `ios/Nudge/Nudge/Changelog.swift`,
`TITLE_FIELD_BUG_HANDOFF.md` (correction banner only).

The bug: double-tapping a word in the reminder title does not reliably select it. The user retested
on 2026-07-28 and confirmed the failure is **intermittent and uncorrelated** — short titles sometimes
work and sometimes don't, and the same is true for long wrapped ones.

The cause is a **gesture-recognizer race**. Two recognizers shared the same hit region on the title
field: the app's own `TapGesture` attached via `simultaneousGesture`, and UIKit's built-in
double-tap-to-select recognizer inside the `TextField`. The `including: titleFocused ? .subviews :
.all` mask was supposed to drop the app's recognizer out of arbitration once the field was focused,
but that mask only re-evaluates on a **SwiftUI render pass**, not synchronously with the touch. So
whether it had taken effect before the second tap landed depended on keyboard animation, scroll
settling and main-thread load. Non-deterministic by construction.

The gesture could not simply be deleted — `TextField(axis: .vertical)` inside a `ScrollView` does not
reliably become first responder from `.focused()` alone on iOS, which is why the assist existed at
all. Deleting it was tried in a previous iteration and broke the keyboard opening.

**The fix:** move the tap-to-focus recognizer *behind* the field, via `.background(...)` instead of
`.simultaneousGesture(...)`. SwiftUI hit-tests front-to-back, so a background layer only receives
touches the `TextField` declined — which is exactly the fallback semantics wanted, and it removes the
shared hit region so the two recognizers can no longer compete.

Applied to both the title field and the notes field (notes still carried the original unmasked
version of the same gesture, so it had the bug in a worse form). `.background(...)` was used rather
than a `ZStack`, because `.background` sizes to the primary view while a `ZStack` containing
`Color.clear` would expand to fill available space and break the layout height.

## Ignore the old handoff's diagnosis

`TITLE_FIELD_BUG_HANDOFF.md` claims the failure correlates with line count (short works, wrapped 2+
lines fails) and with new-vs-existing reminders. **That is wrong.** Those conclusions were single
flaky observations misread as deterministic rules, and each of the three previous iterations was
built on that false premise — which is why they all failed. A correction banner has been added to the
top of that file. Read it for the list of dead ends, not for the reasoning.

(The same handoff also claims a stale uncommitted v2.30 `Changelog.swift` entry exists. It does not —
`Changelog.swift` was clean at 2.29. A fresh 2.30 entry has now been added by this change.)

## The risk — know what failure looks like

This fix is **not guaranteed**, and the user has been told as much. The failure mode to watch for:
if the `TextField` consumes every touch inside its frame *including* the ones where it silently fails
to become first responder, the background gesture will never fire and **the keyboard will stop
opening on tap**. That would reproduce the regression from the earlier "remove the gesture entirely"
iteration.

If you see that, the background approach is dead. Report it and stop.

## Testing — this is where every previous attempt went wrong

The bug is intermittent. **Testing each case once proves nothing.** Every prior iteration was
declared fixed or broken on a single observation, and that is the single biggest reason this bug has
survived three attempts.

Run all four combinations, repeating each **at least five times**, and record the hit rate:

| # | Case | Check A: keyboard opens on tap? | Check B: double-tap selects a word? |
|---|------|--------------------------------|-------------------------------------|
| 1 | New reminder, short single-line title | /5 | /5 |
| 2 | New reminder, long title wrapped to 2+ lines | /5 | /5 |
| 3 | Existing reminder, short single-line title | /5 | /5 |
| 4 | Existing reminder, long title wrapped to 2+ lines | /5 | /5 |

Then repeat all four for the **Notes** field.

Pass condition: **5/5 on both checks for all eight cases.** Anything less is a fail — do not report a
partial pass as a fix. Report the actual hit rates back to the user either way, pass or fail.

Also confirm during testing:

- Scrolling the sheet still works normally (the background gesture must not swallow scroll drags).
- Tapping the title card's **padding** — not the text itself — still opens the keyboard.
- The title card looks visually **identical** to before: same corner radius, same `Theme.surface`
  fill, same hairline border, same width. The fill moved from `.background(Theme.surface, in:)` into
  a `.fill()` on the background shape, so this needs an eyeball check.

## If it fails

Stop. Do not iterate further on gesture arbitration — four attempts have now failed and the tradeoff
does not appear resolvable from SwiftUI's gesture layer.

The agreed fallback is replacing the vertical-axis `TextField` with a `UIViewRepresentable`-wrapped
`UITextView`, which owns the responder directly and gets native focus and native text selection with
nothing competing. That is a real rewrite — auto-grow height, placeholder text, focus binding,
`lineLimit(1...8)` equivalent behaviour and theming all need reimplementing, roughly 120-180 lines in
the app's highest-traffic screen. **Do not start it in this session without checking with the user
first.** Report the failure and the test data and let them decide.

If it fails, also remove the v2.30 `Changelog.swift` entry rather than leaving it describing a fix
that never shipped. Leaving a stale entry in place is exactly what confused the previous session.

## Housekeeping

- Commit only after the on-device test passes 5/5 across all eight cases.
- Push to origin once committed.
- **At the end of the session, remove any stale lock files** — `.git/index.lock` and
  `ios/Nudge/.git/index.lock` — so the next session starts clean.

No API keys, secrets or user data are involved. Nothing here touches Supabase, the Keychain, auth, or
the widget.
