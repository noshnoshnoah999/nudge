# Claude Code prompt — Minimal design round 2 (31 Jul 2026, session C)

Paste everything below the line into Claude Code in the Nudge repo.

---

Read `HANDOFF_2026-07-31c_minimal-design-fixes.md` first. The design decisions were confirmed
with Noah — don't re-plan them. Build, fix compile errors, verify on device, commit, push.

## Context

The Minimal design shipped and Noah's verdict was "it's okay, but it needs a lot of work". Five
complaints, all addressed in this change:

1. Bold Text should be disabled while Minimal is on.
2. **The Settings sheet rendered light while the rest of the app was dark** — a real bug.
3. Reminders were hard to tell apart; he wants visible separation.
4. Hard square outlines around the header icons and the New Reminder sheet's sections.
5. Apple Reminders is now the explicit visual reference for the row layout.

## Step 1 — build

Build for iOS and macOS (Mac Catalyst). Fix compile errors.

Likely sources:

- `AppSettings.swift` gained `import UIKit` and `applyWindowAppearance()`, which touches
  `UIApplication.connectedScenes` and `UIWindow.overrideUserInterfaceStyle`. On Mac Catalyst
  this compiles, but sanity-check it there.
- `Theme.cardSurface(...)` gained a `dividerInset:` parameter (defaulted). `Theme.cardBorderWidth`
  was **removed** — it was unused; if something references it, delete the reference.
- `ReminderCardView.minimalMetaLine(_:)` was **replaced** by `minimalListName(_:)` and
  `minimalTimeLabel(_:)`.
- `iconButton`, `nextUpCard` and `AddReminderView.section(_:_:)` were restructured into
  `if Theme.minimal { … } else { … }` branches. Make sure the `else` branch still produces
  exactly the old view — that's the regression risk.

## Step 2 — the dark-mode bug, and what to do if the fix doesn't hold

The diagnosis: every tinted theme pins `.light`, which SwiftUI implements as
`overrideUserInterfaceStyle = .light` on the UIWindow. Minimal sets the preference to `nil`,
and **nil does not reliably clear an override that's already set**. Sheets inherit their style
from the window, so Settings kept the stale light override while the root rendered dark.

The fix is `AppSettings.applyWindowAppearance()`, which writes `.unspecified` (in minimal) or
`.light` directly to every connected window scene, called from the `minimalDesign` didSet, at
launch, and on foreground.

**Test it like this:** launch on a tinted theme, turn Minimal on, open Settings. That's the
exact path that produced the bug — going straight to Minimal from a fresh install may not
reproduce it.

**If Settings is still light after this change, stop and diagnose rather than trying more
fixes.** Add a temporary `.onAppear` in `SyncSettingsView` that logs
`UITraitCollection.current.userInterfaceStyle` and the presenting window's
`overrideUserInterfaceStyle`, and report the values back. Knowing whether the window override
is stale or whether the trait is being resolved somewhere else determines the correct fix, and
guessing a second time wastes another build.

## Step 3 — verify the layout on device

Compare against the Apple Reminders screenshot Noah sent (its Today list). The row should be:

```
○  Long title wrapping across the full width
   of the row with nothing beside it
   Personal  7:50          ← time red when overdue, list name grey
   ─────────────────────    ← rule starts under the title, NOT under the circle
```

Check specifically:

- The divider's left edge lines up with the title's left edge on every row
  (`Theme.minimalRowTextInset`, 36pt). If it's visibly off, that constant is the one to adjust —
  it's used for both the row spacing and the divider inset so they can't drift.
- Today tab shows `"20:00"`. Overdue tab shows `"9 May, 09:00"`. This is derived from the
  reminder's own due date, not the tab, so also check Home and Search where both kinds mix.
- Only the time is red on an overdue row; the list name stays grey.
- A long title (Noah has several — "Make a daily morning and evening check list…") wraps across
  the full width and is not squeezed or truncated.
- Header icons are bare glyphs. New Reminder sheet has no rectangles around WHEN or the title
  field. "Next up" on Home is a row, not a filled box.

**And check the tinted themes with Minimal off look completely unchanged.**

## Step 4 — report the gaps before committing

The handoff lists what was *not* done. Look at these on device and tell Noah what you see, so
he can decide what's next rather than finding it himself:

- Reschedule, Bulk Move, Triage, Clean Up and the review sheets were not individually rebuilt.
  Any of them with a bordered container will show the same hard-outline problem the New
  Reminder sheet had.
- The FAB is still a filled circle bottom-right; Apple uses a "＋ New Reminder" text button
  bottom-left.
- Capsule chips (AddReminderView's time presets) are unaffected by `Theme.radius`.

## Step 5 — commit and push

Only after a clean build and checking minimal light, minimal dark, and at least one tinted theme.

```
git add -A
git commit -m "Minimal design: Apple Reminders row layout, dark-mode fix, unboxed chrome

Round 2 on Noah's feedback.

- Fix Settings rendering light while the app was dark: preferredColorScheme(nil)
  does not clear an existing overrideUserInterfaceStyle, and sheets inherit the
  window's. applyWindowAppearance() now writes .unspecified/.light directly.
- Disable Bold Text in minimal (effectiveBoldText); dim the toggle to match.
  Bolding every glyph destroys the weight contrast the design relies on.
- Rebuild the minimal row on Apple Reminders: title wraps full width, list and
  time on a second line, time red when overdue. Time only when due today, date +
  time otherwise, derived from the reminder not the tab.
- Inset the row divider to the text column instead of full bleed, and tighten
  rows 13pt -> 10pt. The inset is what makes a row read as one unit.
- Remove the containers rather than squaring them: bare glyph header icons, and
  unboxed sections and title field in AddReminderView. Theme.radius(0) on a
  bordered box makes it louder, not quieter.
- Flatten the Next up card on Home into a row.
"
git push
```

## Step 6 — clean up locks

After the push, remove any git locks or stale locks (`.git/index.lock`, `.git/HEAD.lock`,
`.git/refs/**/*.lock`) so the next session starts clean. Confirm `git status` is clean and no
lock files remain before finishing.

## Report back

Whether it built, whether the Settings dark-mode fix held (and the logged values if not), how
the row compares to the Apple Reminders screenshot, and which remaining sheets still look boxy.
