# Handoff — Minimal design (31 Jul 2026, session B)

**Status:** written in Cowork, **not built, not committed**. Needs Claude Code to build for
iOS + macOS, fix compile errors, test on device, then commit and push.

**Supersedes `HANDOFF_2026-07-31_plain-mode-and-dark-mode.md`.** That work shipped as commit
`85cc7f0` and Noah rejected it on device. This session removes it and replaces it with the
right thing.

## What went wrong the first time

Session A read "minimal, boring, dumb-phone" as a **colour** problem and shipped two extra
palettes, "Plain" and "Plain Dark": neutral greys, corner radius zeroed, animations off.

The structure stayed. Cards still had a fill, a border and a shadow slot — they were just
square and grey. The result read as a washed-out Nudge, not as a minimal app.

What Noah actually wanted was already sitting in the repo: **design 1 ("1 · Minimal") in
`DesignGalleryView`**, a Things-style list. Its defining feature is the **absence of the
container**: no fill, no border, no card — a circle, the title, the time hard right, and a
hairline rule between rows. A minimal list is defined by what isn't drawn.

**The lesson worth keeping: minimal is a layout, not a palette.** Removing colour from a card
still leaves a card.

## What this session does

1. Deletes the `plain` and `plainDark` palettes. `Palette` loses `isDark` and `minimal`.
2. Adds `AppSettings.minimalDesign` — a real, synced, boolean setting.
3. While it's on, the eight palettes are **ignored entirely** and every `Theme` colour returns
   a **UIKit semantic colour**.
4. Deletes `DesignGalleryView.swift` and its "Preview designs (beta)" link in Settings.

### Decisions Noah confirmed before any code was written

| Question | Answer |
|---|---|
| Scope | **Entire app, Settings included** |
| Colour themes in Minimal | **Ignored entirely** — system white/black, grey secondary, red overdue |
| Light vs dark | **Follows iOS system appearance.** No in-app picker |
| Preview designs gallery | **Removed** |

## How "minimal dark mode" works — the one-line version

`AppSettings.colorScheme` returns **nil** when `minimalDesign` is on (it returns `.light` for
the eight tinted themes, exactly as before). Nil hands the decision to iOS. Every minimal
colour is a semantic `UIColor` — `systemBackground`, `label`, `secondaryLabel`, `separator`,
`systemRed` — which resolve themselves per trait collection.

So there is no dark palette, no dark switch, and no second set of hexes to maintain. Turn on
Dark Mode in iOS Settings and Nudge goes black, including the keyboard, sheets and pickers.

This is also why minimal deliberately does **not** offer an in-app Light/Dark/System picker.

## Files changed

### `Theme.swift`

- `Palette` back to its original 9 fields. Both Plain palettes gone.
- New `Theme.minimalDesign` static, set from `AppSettings` (init + didSet), mirroring how
  `Theme.palette` is already set. `Theme.minimal` reads it.
- Every colour now branches: semantic colour in minimal, palette hex otherwise.
  - `accent` in minimal is **`Color(.label)`** — monochrome, black on white / white on black.
    The design has no brand colour. If you ever want the indigo the original preview used,
    that one line is the place.
  - `coral` in minimal is `systemRed` and is **the only colour left anywhere**. Kept on purpose:
    fully greyscale deletes the only at-a-glance signal that something is late.
- `onAccent` / `onTextMain` return `systemBackground` in minimal — the exact inverse of `label`
  in both appearances. This is what stops white-on-white in dark mode.
- `rowInset` is **24pt** in minimal (was 16 in the rejected version), matching the design's
  generous margin. `sectionSpacing` 30pt, `rowVerticalPadding` 13pt.
- **`cardSurface(...)` rewritten.** This is the heart of the fix. In minimal it now applies
  **no fill and no border** — only a 0.5pt hairline underneath, plus an optional 3pt leading
  bar for selection. Previously it kept fill + border and only dropped the radius, which is
  exactly what made session A look wrong.
- Unchanged from session A and still doing the heavy lifting: `Theme.spring/snappy/bouncy`
  return `.linear(duration: 0)` in minimal; `Theme.radius(N)` returns 0 (still wrapping all 86
  `RoundedRectangle` sites); `popIn` and `cardElevation` are no-ops.

### `ReminderCardView.swift`

- `cardBody` now branches to **`minimalBody`** or `tintedCardBody`. A separate body, not
  `if minimal` sprinkled through the card — that was session A's mistake.
- `minimalBody` is the design-1 row: circle · title · right-aligned time, 13pt vertical
  padding, hairline underneath.
- Everything the tinted card shows as chips, pills and capsules (list name, priority, repeat,
  subtask count, location, link, photo, source badge) collapses into **one quiet grey line** of
  plain text — `"Money · every 7d · 2/3 · school"` — and only when there's something to say.
  Most rows stay single-line, like the design.
- **"Ask Claude" is kept** in minimal, as plain underlined text rather than a filled pill. It's
  a function, not decoration, and dropping it would have been a real regression. Its action was
  factored out into `askClaude(_:)`, shared by both bodies.
- `completeWithFlair` still early-returns in minimal: tick and move on, no gold trace, no
  slide-off, no haptic, no chime.

### `ContentView.swift`

- The progress hero (big number + progress ring in a filled card) is **not rendered at all** in
  minimal. The header already gives the date and the status line already gives the count, so
  only the gauge is lost.
- Section headers: count pill (a filled capsule) hidden in minimal; tracking 1; 8pt below.
- Header subtitle in minimal is ordinary grey sentence case ("Saturday 6 June") instead of
  tracked accent caps — with a black accent, caps read as a second heading.
- Page inset `Theme.rowInset`; section gap `Theme.sectionSpacing`; rows flush inside a section.
- Carry-over and grouping banners stay as session A left them: flat rows, no gradient, no
  forever-pulsing glow in minimal.

### `GroupCardView.swift`

- Group header uses `cardSurface`, so it's a hairline row in minimal rather than the one
  remaining squared-off box.
- The expanded group's **2pt dark-orange wrapper box is dropped** in minimal; members are
  indented 14pt under the header instead, the way a nested list shows nesting.

### `AppSettings.swift` + `NudgeStore.swift` — sync

`minimalDesign` joins `theme` / `boldText` / `compact` in the existing per-user Supabase
`settings` row. Same whole-value, most-recent-wins path, same ping-pong guard. No new table.

Two migration details that matter:

- **`init`**: anyone sitting on the now-deleted `"plain"` / `"plainDark"` theme id is moved to
  Mocha **with `minimalDesign` turned on** — which is what they were reaching for anyway.
- **`applyFromCloud`**: same translation for a dead theme id arriving *from the cloud*. Without
  it, `Palettes.by("plainDark")` would silently fall back to Mocha while `theme` still held the
  dead id, and the next local change would push that dead id straight back up. This matters
  because commit `85cc7f0` is already on Noah's devices, so a dead id may genuinely be sitting
  in the cloud row right now.
- `seedAppearanceIfMissing` still guards on the original three keys only. A row written by an
  older build has no `minimalDesign`; that reads as nil (= off) until toggled, which is right.

### `SyncSettingsView.swift`

- **"Minimal design" toggle at the top of Appearance**, above the theme picker.
- The theme picker and "Sound & haptics" are **disabled and dimmed to 0.4** while Minimal is
  on, rather than silently doing nothing when tapped.
- Footer copy changes depending on the switch, and tells you to use iOS Settings for dark mode.
- "Preview designs (beta)" link removed.

### Deleted

`DesignGalleryView.swift`. `Nudge/` is a synchronized group in the xcodeproj
(see the xcodeproj memory), so **no `project.pbxproj` edit is needed** — verified: the file
had 0 references there.

### `Changelog.swift`

The 2.30 entry is rewritten from "Plain mode & dark mode" to "Minimal design & dark mode".

## Known gaps — be honest about these on device

1. **Never compiled.** No Swift toolchain in the Cowork sandbox. Brace/paren balance was
   scripted across every file and is clean, but that is not a build.
2. **"Entire app including Settings" is only partly true.** Settings is a system `Form`; in
   minimal it now renders with `systemBackground` rows and follows dark mode, which is the
   important part, but it was not restructured. Sheets (Add Reminder, Reschedule, Bulk Move,
   Triage) inherit minimal colours and squared corners via `Theme.radius`, but their internal
   layouts were **not** rebuilt as hairline lists. If those still look card-like, that's the
   next chunk of work, and it's a big one.
3. **Capsule chips survive in the sheets.** `Capsule()` shapes aren't affected by
   `Theme.radius`. The main list no longer uses them (the minimal row has no chips), but
   AddReminderView's time presets and similar still do.
4. **The tab bar keeps `.ultraThinMaterial`.** Correct in dark mode, but it is a material, not
   a flat fill. Judge it on device.
5. **Bold Text interacts.** The screenshot was taken with Bold Text on, which is why design 1
   looks heavier there than `.font(.body)` will render by default. If minimal looks too light
   versus the screenshot, that's the Bold Text setting, not a bug.

## Test checklist for Claude Code

- [ ] Builds for iOS and macOS (Mac Catalyst).
- [ ] **The 8 tinted themes look completely unchanged with Minimal off.** Main regression risk.
- [ ] Minimal on, iOS in Light: matches the screenshot — no cards, hairlines between rows,
      circle / title / right-aligned time, red OVERDUE header, 24pt margins.
- [ ] Minimal on, iOS in Dark: whole app black including keyboard, sheets, date wheels, context
      menus. No white flashes, no white-on-white text.
- [ ] Every accent-filled button is readable in minimal dark (accent is white there, so any
      surviving hardcoded `.white` label will be invisible): Move, Use this time, Move N
      Reminders, Keep, Unlock, Add to Nudge, Find a time, Reschedule overdue now, Ask Claude.
- [ ] Undo toast, selection bar and simple toast readable in minimal dark.
- [ ] Completing a reminder in minimal just ticks it — no gold trace, slide, sound or haptic.
- [ ] Selected rows are still obviously selected (3pt leading bar), and overdue is still obvious.
- [ ] Groups: header is a plain row, expanded members indent, no orange box.
- [ ] Settings: Minimal toggle is above the theme picker; picker dims when Minimal is on;
      "Preview designs (beta)" is gone.
- [ ] **Anyone on the old Plain palette lands on Mocha + Minimal on**, not on a broken theme.
      Test by setting theme to Plain on the old build first, if that's still reachable.
- [ ] Minimal setting propagates iPhone ↔ MacBook.
