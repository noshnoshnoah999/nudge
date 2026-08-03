# Claude Code prompt — Today widget tap-complete + styling — 2026-07-24 (b)

Paste this into the Nudge Claude Code session. Full detail:
`HANDOFF_2026-07-24b_widget-tapcomplete-styling.md`.

---

## Context

Two new Today-widget features written in Cowork (not built yet):
1. **Tap-to-complete** — tap a reminder row in the Today widget to mark it done without opening
   the app. Because `NudgeStore` is app-target-only, the completion is written **directly to the
   per-item `reminders` table** from a shared AppIntent.
2. **Edit-mode styling + Dumb-Phone look** — long-press Today → Edit → Font / Font size (numeric
   stepper 12–40pt) / Spacing / Grayscale, via an `AppIntentConfiguration` (no App Group needed).
   The Today list is restyled to look like the "Dumb Phone" launcher: each row is just the
   reminder title — forced **lowercase**, **bold**, **left-aligned**, big — no coloured ring,
   no due-date label. Long titles cut off cleanly at the edge with **no ellipsis**. `maxRows`
   now scales with the chosen font size so big text doesn't overflow.

   Note: the font size uses `@Parameter(controlStyle: .stepper, inclusiveRange: (12,40))`. If you
   (or Noah) prefer a drag slider, change `.stepper` to `.slider` — both are valid.

**Files:**
- New: `ios/Nudge/Shared/CompleteReminderWidgetIntent.swift`
- New: `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
- Changed: `ios/Nudge/NudgeWidgets/NudgeWidgets.swift` (Today widget → AppIntentConfiguration;
  rows wrapped in `Button(intent:)`; style applied). Other 4 widgets unchanged.

## Do this, in order (confirm understanding first)

1. **Read** the handoff and the three files/diffs. Play back your understanding.

2. **Build** app + NudgeWidgets. Fix compile issues. Most likely nitpick:
   `AppEnum.caseDisplayRepresentations` may need to be a computed `static var` on your SDK
   rather than a stored one — adjust if the compiler asks. Braces/parens verified balanced.

3. **Test tap-to-complete on-device:**
   - Tap a reminder in the Today widget → it should complete WITHOUT opening the app, drop off
     the widget, and show as completed in the app and other devices after sync.
   - Test a one-off reminder (should be perfect).
   - Test a RECURRING reminder: it completes, but its next occurrence only appears after you open
     the app (documented limitation — the widget can't run the app's recurrence logic). Confirm
     that's the behaviour, not a crash or a lost reminder.
   - Confirm the completion isn't clobbered by the app's next sync (it stamps a fresh updated_at).

4. **Test edit-mode styling + Dumb-Phone look:** long-press Today → Edit Widget → change Font,
   Font size (numeric stepper), Spacing, Grayscale → each should visibly change the widget.
   Confirm the list looks like the Dumb-Phone launcher: lowercase, bold, left-aligned titles,
   no rings/dates, long titles cut cleanly with no "…". Grayscale only shows in FULL-COLOUR home
   screen mode (tinted mode already strips colour). Watch that large font sizes don't overflow
   the widget (maxRows should adapt) — if it does, nudge the `usableHeight` estimate in maxRows.

5. **Expect to re-place the Today widget once** — switching it to AppIntentConfiguration resets
   already-placed Today widgets. Re-add it and pick options. One-time, not data loss.

6. **Commit** (e.g. `Today widget: tap-to-complete + edit-mode font/size/spacing/grayscale`).

7. **Push.**

8. **After committing and pushing, remove any git locks / stale locks** (`.git/index.lock`,
   `.git/refs/**/*.lock`, any `*.lock`) so the next session starts clean.

## LAYOUT FIX (2026-07-24, after on-device test showed breakage)

Noah tested and the Dumb-Phone rows overflowed off BOTH edges (text spilling left, right, and
centre) with big vertical gaps. Cause: `.fixedSize(horizontal:true)` directly on the Text sized
it to full natural width ignoring the widget bounds, and `.clipped()` clipped from centre.

Fixed by wrapping each row title in `HStack(spacing:0){ Text…fixedSize; Spacer(minLength:0) }`
then `.frame(maxWidth:.infinity, alignment:.leading).clipped()` — text pinned left, sliced on the
right only, no "…". THIS NEEDS ON-DEVICE VERIFICATION (Cowork can't render SwiftUI):
- Confirm long titles cut off cleanly on the RIGHT edge only, no overflow left/centre, no "…".
- Confirm rows stack tightly from the TOP with even spacing (no huge gaps). If gaps persist,
  tune `maxRows` `usableHeight` (currently 130 medium / 320 large) and/or the VStack spacing.
- Confirm TAP-TO-COMPLETE still hits the right row — the clip+fixedSize+Button combo can enlarge
  the tap target to the text's natural (overflowing) width. If taps feel off, constrain the
  Button's content width or move `.contentShape(Rectangle())` onto the clipped frame.

## Rules / safety
- The tap-complete write uses the anon key + the user's Keychain bearer token; RLS on `reminders`
  scopes it to the signed-in user. No service-role key anywhere. Keep it that way.
- If tap-complete ever writes the WRONG user's row or fails RLS, STOP — that's a security issue,
  report it before committing.
- Don't paste keys anywhere.
- If the on-device test shows completions bouncing back after app sync, STOP and report — it
  would mean the updated_at stamping isn't outranking the app's copy.
