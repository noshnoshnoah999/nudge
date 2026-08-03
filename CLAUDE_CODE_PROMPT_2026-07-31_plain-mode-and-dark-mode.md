# Claude Code prompt — Plain mode & Dark mode (31 Jul 2026)

Paste everything below the line into Claude Code in the Nudge repo.

---

Read `HANDOFF_2026-07-31_plain-mode-and-dark-mode.md` in the repo root first — it explains the
whole change and lists the known compromises. Do not re-plan the feature; it is already written.
Your job is to build it, fix compile errors, verify it on device, then commit and push.

## Context

A Cowork session added two new themes — **Plain** and **Plain Dark** — to the iOS/macOS app.
They are deliberately low-stimulation ("dumb phone" style, modelled on Apple Reminders), and
Plain Dark is Nudge's first real dark theme. The code is written but **has never been compiled**
— there is no Swift toolchain in the Cowork sandbox.

The mode is a property of the palette (`Palette.minimal` / `Palette.isDark`), not a new setting,
so it rides the existing `theme` cross-device sync key with no new sync surface.

## Step 1 — build

Build the Nudge scheme for iOS and for macOS (Mac Catalyst). Fix any compile errors.

Two changes are the most likely sources of errors:

1. **`Theme.spring` / `Theme.snappy` / `Theme.bouncy` changed from `static let` to computed
   `static var`.** They now return `.linear(duration: 0)` when the palette is minimal. If
   anything expected a `let`, fix the call site rather than reverting the change — the
   zero-duration trick is what makes every existing `withAnimation(Theme.spring)` call
   automatically become a no-op in Plain mode. Reverting it breaks the whole feature.
2. **A script rewrote 86 `RoundedRectangle(cornerRadius: N, ...)` call sites across 20 files**
   to `RoundedRectangle(cornerRadius: Theme.radius(N), ...)`. If any of those landed inside a
   context where `Theme` isn't in scope, or where the argument was already an expression that
   now type-checks differently, fix it in place. Do not undo the transform wholesale.

Also new and unused-until-now: `Theme.onAccent`, `Theme.onCoral`, `Theme.onTextMain`,
`Theme.radius(_:)`, `Theme.cardBorderWidth`, `Theme.rowInset`, and the `cardSurface(...)` view
modifier in `Theme.swift`.

## Step 2 — verify on device (iPhone), then quickly on the Mac

Work through the checklist at the bottom of the handoff. The four things most likely to be
wrong, in order:

1. **Existing themes regressed.** Mocha/Sage/Rose/Lavender/Graphite/Ocean/Orange/Red must look
   exactly as they did before. This is the main risk of the radius transform and the
   `.white` → `Theme.onAccent` replacements. Compare against the current App Store-installed
   build if you can.
2. **Unreadable text in Plain Dark.** Plain Dark's accent is a *light* grey (`AEAEB2`), which
   inverts the app's old assumption that accents are always dark. Every button with text on an
   accent fill, plus the undo toast / selection bar (which fill with `Theme.textMain` = white
   in Plain Dark), must be checked. If you find one that's still hardcoded `.white`, point it
   at `Theme.onAccent` (accent fills), `Theme.onCoral` (coral fills) or `Theme.onTextMain`
   (toast bars).
   Deliberately left as literal `.white`: the photo-viewer close buttons in `AddReminderView`
   (~line 63 and ~line 1080, on a black photo backdrop) and `DesignGalleryView:125`.
3. **System chrome not going dark.** `AppSettings.colorScheme` now returns `.dark` for
   Plain Dark. Check the keyboard, sheets, date-picker wheels, context menus and the tab bar's
   `.ultraThinMaterial`.
4. **Plain mode's 16pt page inset reading as too card-like.** See compromise #1 in the handoff.
   If it looks wrong on device, set `Theme.rowInset` to `0` for minimal and add explicit
   horizontal padding to the section headers and empty-state text in `ContentView`.

Also confirm: completing a reminder in Plain mode just ticks it (no gold trace, no slide-off,
no sound, no haptic), the carry-over and grouping banners are flat grey and do not pulse, and
selected/overdue cards are still obviously distinguishable.

## Step 3 — sync check

Change the theme to Plain Dark on the iPhone and confirm the MacBook picks it up (and back).
This path was **not modified** — it's the existing `theme` key in the Supabase settings row with
its ping-pong guard — so if it's broken, something in `AppSettings` regressed. Do not add a new
settings key to fix it.

## Step 4 — commit and push

Do not commit until the build is clean and you've eyeballed both Plain themes plus at least two
tinted themes on device.

```
git add -A
git commit -m "Add Plain and Plain Dark themes (minimal/low-stimulation mode + first dark mode)

Plain and Plain Dark are palette-level modes: Palette gains isDark and minimal
flags, so selecting the theme IS the switch and it rides the existing cross-device
theme sync key with no new settings surface.

- Theme.spring/snappy/bouncy become zero-duration in minimal mode, so every
  existing withAnimation call is a no-op without per-view branching
- Theme.radius() squares off all 86 RoundedRectangle sites from one place
- New cardSurface() modifier: rounded card normally, flat row + hairline in Plain
- popIn and cardElevation become no-ops; completion flair, haptic and chime skipped
- Carry-over and grouping banners drop their gradients and forever-pulsing glow
- AppSettings.colorScheme was hardcoded .light; now palette-driven so Plain Dark
  takes the keyboard, sheets and pickers dark with it
- New Theme.onAccent/onCoral/onTextMain replace ~30 hardcoded .white sites that
  assumed a dark accent — false for Plain Dark, whose accent is light grey
- Changelog 2.30
"
git push
```

## Step 5 — clean up locks

After the push completes, remove any git locks or stale locks left behind
(`.git/index.lock`, `.git/HEAD.lock`, `.git/refs/**/*.lock`) so the next session starts clean.
Confirm `git status` is clean and the working tree has no leftover lock files before you finish.

## Report back

Tell me: whether it built, what you had to fix, anything that looked wrong on device, and
whether the 16pt Plain inset should be dropped to 0.
