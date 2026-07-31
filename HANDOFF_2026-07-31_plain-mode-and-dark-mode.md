# Handoff — Plain mode & Dark mode (31 Jul 2026)

**Status:** written in Cowork, **not built, not run, not committed**. Needs a Claude Code
session to build for iOS + macOS, fix any compile errors, test on device, then commit and push.

## What was asked

> "Add a setting to make a minimal, boring (dumb phone style) Nudge design to match the Apple
> Reminders app — want to try to make me bored of my phone — add dark mode."

Decisions confirmed with Noah before any code was written:

| Question | Answer |
|---|---|
| Structure | Two new palettes ("Plain", "Plain Dark") in the existing theme picker — not a separate toggle |
| Strip level | Colour + shadows, animations, completion celebration, rounded cards → flat rows (all four) |
| Sync | Syncs across devices (rides the existing `theme` key) |
| Widget | "Match the widget too" — see *Widget* section; concluded no code change needed |

## Honest note recorded at the time

A boring reminders app will not reduce phone use. Reminders is a 15-second utility; the
attention sinks are elsewhere. OS-level greyscale (Accessibility → Colour Filters) plus Screen
Time does far more for zero code. The feature is still worth having on its own merits — Nudge
had no neutral theme and no dark mode at all — but it should not be expected to change screen
time. Noah was told this before the work started.

## Design decision: plain mode is a *palette property*, not a new setting

`Palette` gained two fields:

```swift
var isDark: Bool = false    // drives the app's colorScheme
var minimal: Bool = false   // the low-stimulation switch
```

Selecting "Plain" or "Plain Dark" IS the switch. This was deliberate:

- No new UserDefaults key, no new Supabase settings key, no migration.
- It rides the **existing** `theme` cross-device sync path (`AppSettings.SyncKey.theme`),
  which is already tested and already has the ping-pong guard. Zero new sync surface.
- `Theme.minimal` / `Theme.isDark` are computed from `Theme.palette`, so any code can read the
  mode without holding an `AppSettings`.

Trade-off: you cannot have "dark Mocha" or "minimal Ocean". Combining them would have meant a
second synced key and a 2×9 colour matrix to sanity-check. If that's wanted later, the split is
straightforward — `minimal` and `isDark` become their own `@Published` props and each palette
gets a dark variant.

## Files changed

### `Theme.swift` — the core of the change

- `Palette` + `isDark`, `minimal`.
- Two new palettes appended to `Palettes.all`:
  - `plain` — Apple system greys. bg `F2F2F7`, card `FFFFFF`, hairline `D1D1D6`, text `000000`,
    textSoft `8E8E93`, accent `3A3A3C`.
  - `plainDark` — bg `000000`, card `1C1C1E`, cardStrong `2C2C2E`, hairline `38383A`,
    text `FFFFFF`, textSoft `8E8E93`, accent `AEAEB2`.
- **`Theme.spring` / `snappy` / `bouncy` changed from `static let` to computed `static var`**
  and return `.linear(duration: 0)` in plain mode. This is why almost no view needed an
  `if minimal` branch for motion — every existing `withAnimation(Theme.spring)` call keeps
  working and simply doesn't move. *If a build error mentions these, it's because something
  expected a `let`.*
- `Theme.radius(_ normal:)` returns `0` in plain mode, `normal` otherwise.
- `Theme.cardBorderWidth`, `Theme.rowInset` (16 plain / 18 normal).
- **New on-fill colours** — `Theme.onAccent`, `Theme.onCoral`, `Theme.onTextMain`.
  See the next section; this was the biggest hidden landmine.
- `Theme.sage` (the "done" green) neutralises to `textSoft` in plain mode.
- `Theme.coral` gains `plain` / `plainDark` cases so overdue stays legible.
- `cardElevation()` and `popIn()` are now `@ViewBuilder` no-ops in plain mode.
- `PressableStyle` drops its press-scale in plain mode.
- **New `cardSurface(radius:fill:border:borderWidth:)` view modifier** — the single place card
  geometry is decided. Rounded bordered card normally; flat fill + bottom hairline in plain.

### The `.white` landmine (the part most likely to have been missed)

All eight tinted palettes have a **dark** accent, so ~30 views hardcoded `.white` for text
sitting on an accent-filled shape. `plainDark`'s accent is a **light** grey (`AEAEB2`) — it has
to be, because the accent doubles as text on a black page. White-on-`AEAEB2` is unreadable.

Same problem with the toast/selection bars, which fill with `Theme.textMain` — white in
`plainDark`, so white text on them would be invisible.

Every affected site now asks for `Theme.onAccent` / `onCoral` / `onTextMain`. Changed in:
`ReminderCardView`, `RoutineCheckInView`, `ScanReminderView`, `TimetableView`, `MiniCalendar`,
`QuickCatchView`, `AddReminderView`, `LocationPickerView`, `RescheduleOptionsView`,
`BulkMoveView`, `TriageView`, `LockShield`, `ContentView` (toasts, selection bar, smart
reschedule button, overdue count pill, `reverseText`, expiry banner).

**Deliberately left as literal `.white`:** the photo-viewer close buttons in `AddReminderView`
(lines ~63, ~1080 — they sit on a black photo backdrop) and `DesignGalleryView:125` (a demo
hero on its own dark gradient). Check these two on device anyway.

### `AppSettings.swift`

- `colorScheme` was **hardcoded `.light`**. Now `Palettes.by(theme).isDark ? .dark : .light`.
  Without this, Plain Dark would have been a black page with a white keyboard and white sheets.
  The eight tinted palettes still force `.light` exactly as before — no regression there.
- Added `var minimal: Bool` convenience.

### `ContentView.swift`

- Scroll container: row gap → 0 and inset → `Theme.rowInset` in plain; tab transition → `.identity`.
- `progressHero`: drops the progress ring entirely, and the 30pt heavy number becomes
  `.title3.semibold` reading "3 of 7 done".
- `carryOverBanner` (red gradient + forever-pulsing glow) and `groupBanner` (orange, same)
  become **flat `Theme.surface` rows with a hairline** in plain mode, and the
  `.repeatForever` animation is `guard`ed off. These two were the loudest elements in the app.
- `reverseText` → `Theme.onAccent`.

### `ReminderCardView.swift`

- Card shape moved to `.cardSurface(...)`. Selection (2.5pt) and overdue (2.5pt) still draw a
  visible outline **even in plain mode** — boring must not mean "can't tell what's selected".
- `completeWithFlair()` early-returns in plain mode: plain `store.toggleComplete(r)`, no gold
  trace, no slide-off, no haptic, no `AudioServicesPlaySystemSound`.

### Mechanical change across 20 files (86 sites)

Every `RoundedRectangle(cornerRadius: N, ...)` became
`RoundedRectangle(cornerRadius: Theme.radius(N), ...)`. Radius 0 renders as a plain rectangle,
so this squares the whole app off from one place instead of rewriting 86 views. Applied by
script; verified no double-wrapping (`Theme.radius(Theme.radius(` count = 0).

### `SyncSettingsView.swift`

- Theme grid now 3 rows of 4 (10 palettes). Unselected swatch rings contrast with their own
  background — the old faint black ring was invisible on the near-white and near-black swatches.
- Footer copy explains what Plain does.

### `Changelog.swift`

New 2.30 entry, "Plain mode & dark mode", 31 Jul 2026.

## Known compromises — read before testing

1. **Not truly edge-to-edge.** `Theme.rowInset` is 16pt in plain mode, not 0. True Apple
   Reminders full-bleed would leave section headers ("TODAY", "OVERDUE") and empty-state text
   flush against the screen edge, which looks broken. Fixing that properly means re-padding
   text separately from rows across six tabs. Squared corners + zero row gap + hairlines
   already carry the list feel. **Revisit on device** — if it still reads as card-like, the fix
   is to set `rowInset` to 0 and add per-header padding.
2. **Capsule chips are untouched.** Due chips, priority pills and the "Ask Claude" button are
   still `Capsule()` shapes. Apple Reminders uses plain text. Left alone as low-value / high
   churn; easy follow-up if it looks off.
3. **Overdue keeps colour.** Plain is greyscale *except* overdue, which keeps a muted red
   (`A03A28` light / `C97567` dark). Fully greyscale would delete the only at-a-glance signal
   that something is late — a real usability loss, not a style choice.
4. **Never compiled.** There is no Swift toolchain in the Cowork sandbox. Brace/paren balance
   was checked by script across every file and came back clean, but that is not a compile.
   Expect to fix small type errors in Claude Code.

## Widget — no code change, and why

Noah picked "match the widget too". After reading `NudgeWidgets/TodayWidgetStyle.swift`: the
widget **already has this**. Its Edit mode (long-press → Edit Widget) exposes a **Grayscale**
toggle plus **Soft Black (#0B0B0B) / True Black (#000000)** backgrounds, font, text size and
row spacing — that is Plain Dark for the widget, and it already ships.

Making the widget *automatically* follow the app's theme is not possible the easy way: this
project builds under a **free Apple team, so there are no App Groups** and no shared
UserDefaults. It would need a new Keychain-access-group mirror of the theme value (the same
trick `AuthStore` and `WidgetBackgroundImageStore` already use). That is real new machinery —
a Keychain read on every widget render, plus a write path from the app — for a result Noah can
get in three taps today. **Recommended against; not built.** Say the word if you want it.

To match by hand: long-press the Today widget → Edit Widget → Grayscale on, Background = True
Black.

## Test checklist for the Claude Code session

- [ ] Builds for iOS and macOS (Mac Catalyst) with no errors.
- [ ] Existing 8 tinted themes look **byte-for-byte unchanged** — this is the main regression risk.
- [ ] Plain Dark: keyboard, sheets, date-picker wheels, context menus and the tab bar material
      are all dark. No white flashes.
- [ ] Plain Dark: every button with text on an accent fill is readable (Move, Use this time,
      Move N Reminders, Keep, Unlock, Add to Nudge, Recommended, Ask Claude, Step up, Yes did it,
      Use this location, Find a time, Reschedule overdue now, Smart Reschedule).
- [ ] Plain Dark: undo toast, selection bar and simple toast are readable (white-on-white check).
- [ ] Plain: no pop-in on tab switch, no card shadows, no progress ring.
- [ ] Plain: completing a reminder just ticks it — no gold trace, no slide, no sound, no haptic.
- [ ] Plain: carry-over and grouping banners are flat grey and do not pulse.
- [ ] Selected and overdue cards are still obviously distinguishable in Plain.
- [ ] Theme change propagates iPhone ↔ MacBook (existing sync path — should be untouched).
- [ ] Photo viewer close buttons in AddReminderView still visible.
