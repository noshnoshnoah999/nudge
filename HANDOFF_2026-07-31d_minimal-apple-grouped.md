# Handoff — Minimal design, round 3: Apple grouped style (31 Jul 2026, session D)

**Status:** written in Cowork, **not built, not committed.** Needs Claude Code to build, fix
compile errors, test on device, commit, push.

Follows `HANDOFF_2026-07-31c_minimal-design-fixes.md`. Three complaints from Noah, plus a
mid-session "there are still outlines here" with screenshots of the Home stat tiles and the
Lists grid.

## I had the rule backwards, and this session corrects it

Round 2's rule was *"remove the container, don't square it."* That is right for the reminder
**list** and wrong for everything else, and it's why outlined boxes kept reappearing.

Noah's screenshot 3 — the Apple Reminders **edit** screen — settles it. Reminders uses grouped
cards everywhere except its list: the title/notes/URL block, Date & Time, Repeat/Early Reminder
are all filled, softly rounded cards. So the actual rule is:

> **Apple separates a card from the page with a FILL, never with a stroke — and the corners are
> rounded, not square.**

Every "there are still outlines" report traced to the same two mistakes:

1. `Theme.surface` in minimal was `systemBackground`, i.e. **the same colour as the page**. The
   card fill was invisible, so all you saw was its border. Hollow rectangles everywhere.
2. `Theme.radius(N)` returned **0**, squaring every container. A squared, bordered box is
   *louder* than a rounded one, not quieter.

### The fix, in three lines of Theme

- `Theme.surface` (minimal) → `secondarySystemBackground`. A visible dark grey card on a black
  page, exactly like a grouped cell. `surfaceAlt` → `tertiarySystemBackground`.
- **New `Theme.cardStroke`** → `.clear` in minimal, `hairline` otherwise. All 18
  `.stroke(Theme.hairline)` / `.strokeBorder(Theme.hairline)` sites on rounded rects were
  swept over to it by script, across 9 files. `Theme.hairline` still means "divider between
  rows" — only borders around a shape changed.
- `Theme.radius(N)` (minimal) → `min(N, 10)` instead of 0. Grouped-card rounding.
  **The reminder rows are still perfectly square** because they pass 0 explicitly through
  `cardSurface` and draw no shape at all.

This is a single systematic fix rather than 18 individual ones, which is what the last two
rounds were doing wrong — Noah found the Home tiles, the Lists grid and the Notion button one
screenshot at a time.

## The three named complaints

### 1. "The Minimal design toggle looks strange"

In dark mode the ON switch was a white track under a white knob — invisible. Cause:
`NudgeApp` applies `.tint(settings.accent)` app-wide, SwiftUI tints `Toggle` with it, and
minimal's accent was `Color(.label)` = white.

Two changes:

- **`Theme.accent` in minimal is now `Color(.systemBlue)`**, not `label`. Monochrome was my
  invention, not the reference: Reminders is a minimal app *with* one accent colour — its
  title, its values ("Today", "7:50"), its ＋ and its confirm button are all blue.
- **`Theme.controlTint` / `AppSettings.controlTint` return nil in minimal**, so controls fall
  back to iOS defaults — a **green** switch and a blue caret, exactly like Reminders.
  All 46 `.tint(Theme.accent)` / `.tint(Theme.violet)` sites were swept to `Theme.controlTint`.

### 2. The Notion icon was the last one with an outline

`iconButton` got a minimal branch in round 2, but the Notion button is **hand-rolled** — it has
an in-flight `ProgressView` — so it never went through `iconButton` and the branch never
reached it. Now bare in minimal like the others.

### 3. Match the Reminders edit sheet

Round 2 stripped `AddReminderView`'s sections and title field down to full-bleed rows between
hairlines. That was the misreading described above. **Both are back to filled rounded cards**,
which in minimal now means a system fill, 10pt corners and a transparent stroke.

## Files changed

- `Theme.swift` — `surface`/`surfaceAlt` to secondary/tertiary system backgrounds; new
  `cardStroke`; new `controlTint`; `accent` → systemBlue in minimal; `radius` clamps to 10.
- `AppSettings.swift` — new `controlTint`.
- `NudgeApp.swift` — `.tint(settings.controlTint)`.
- `ContentView.swift` — Notion header button unboxed in minimal.
- `AddReminderView.swift` — `section(_:_:)` and the title field restored to cards.
- 9 files — 18 border sweeps; 18 files — 46 tint sweeps (both by script).

## What this does NOT fix

1. **Never compiled.** No Swift toolchain in Cowork. Brace/paren balance scripted and clean.
2. **The tab bar's selected pill** is `accentSoft`, now a blue wash. Reminders has no pill at
   all. Left alone — judge it on device.
3. **The FAB** is still a filled circle bottom-right. Reminders uses a "＋ New Reminder" text
   button bottom-left. Still not asked for.
4. **Capsule chips** (AddReminderView's time presets) aren't affected by `Theme.radius`.
5. **Home is still Nudge-shaped**, not Reminders-shaped — stat tiles and a Lists grid are
   Nudge's own ideas. They now *look* like Apple grouped cards, but Reminders has no equivalent
   screen. If Noah wants Home restructured that's a separate, bigger job.
6. `Theme.accent` going blue means blue now appears in the tinted themes' … no — it's gated on
   `minimal`, the 8 palettes are untouched. But **do check a tinted theme**, since `accentSoft`
   and `controlTint` changed shape for both paths.

## Test checklist

- [ ] Builds for iOS and macOS.
- [ ] **Minimal OFF is completely unchanged.** The tint and border sweeps touched ~64 sites
      across both paths — this is the big regression risk this round.
- [ ] No hollow outlined rectangles anywhere in minimal: Home stat tiles, Lists grid, Notion
      button, Settings rows, New Reminder sections, Changelog, Triage, Bulk Move, Reschedule.
- [ ] Cards are visibly darker than the page in minimal dark, and lighter than the page in
      minimal light. **Check light mode too** — `secondarySystemBackground` is a light grey
      there, and if it reads as muddy against `systemBackground` say so.
- [ ] Toggles are green when on, with a visible knob, in Settings and New Reminder.
- [ ] Reminder rows are still square and flat with an inset divider — they must NOT have picked
      up the 10pt radius or a fill.
- [ ] New Reminder sheet next to the Reminders edit screenshot: grouped rounded cards, grey
      section captions, blue values, green switches.
