# Handoff — Minimal design, round 2 fixes (31 Jul 2026, session C)

**Status:** written in Cowork, **not built, not committed.** Needs Claude Code to build, fix
compile errors, test on device, commit, push.

Follows `HANDOFF_2026-07-31b_minimal-design.md`. That build shipped and works, but Noah's
verdict was *"it's okay, but it needs a lot of work"*, with five specific complaints. This
session fixes all five. **Apple Reminders is now the explicit visual reference**, confirmed by
Noah with a screenshot of its Today list.

## The five complaints and what was done

### 1. Bold Text should be off in Minimal

`NudgeApp` applied `.fontWeight(settings.boldText ? .bold : nil)` at the root, which bolds
every glyph in the app.

New `AppSettings.effectiveBoldText` = `boldText && !minimalDesign`; the root now reads that.
The Settings toggle is disabled and dimmed in minimal so the UI agrees with the behaviour.

Worth noting *why* this matters beyond preference: the minimal design's whole legibility model
is weight contrast — a regular-weight body against a heavy title and a grey second line.
Bolding everything collapses that into a wall of black text, which is a real part of why the
first minimal screenshots looked mushy.

### 2. Settings page rendered LIGHT while the rest of the app was dark

This was a genuine bug, and the cause is worth writing down because it will bite again.

Every tinted theme pins `.light`, which SwiftUI implements by setting
`overrideUserInterfaceStyle = .light` on the **UIWindow**. Minimal changes the preference to
`nil` — "no preference" — and **nil does not reliably clear an override that is already set**.
Sheets take their interface style from the window they're presented in, so the root re-rendered
dark (its semantic colours resolve against the system trait) while the Settings sheet kept the
stale light override.

Fix: `AppSettings.applyWindowAppearance()` writes the style to every connected window scene
directly — `.unspecified` in minimal (which *does* clear it), `.light` otherwise. Called from
the `minimalDesign` didSet, at launch, and on every foreground (a scene can be rebuilt).
`preferredColorScheme` stays as-is; the two agree, they don't fight.

**If this doesn't fix it on device, do not guess** — see the diagnostic in the Claude Code prompt.

### 3. Hard to tell individual reminders apart

Two changes, and the less obvious one is doing most of the work.

- **The divider is now inset** to start where the *text* starts (`Theme.minimalRowTextInset`,
  36pt), not at the circle — the way Reminders, Mail and Settings all draw list rules. The
  inset is what makes a row read as one object: the rule belongs to the text column, so the
  circle and its title group together. A full-bleed rule instead slices the screen into
  horizontal bands and the rows stop feeling like units. Noah chose "inset + subtle" over
  "brighter line", which is the right call — **brightness was the obvious fix and the wrong one**.
- **Rows are tighter**: `Theme.rowVerticalPadding` 13 → 10. At 13pt with a full-bleed rule the
  rows read as floating blobs of text rather than a list.

### 4. Square outlines around the header icons

`iconButton` drew a filled rounded rect plus a 1pt border. `Theme.radius(12)` → 0 turned that
into a hard square outline — *worse* than the rounded original, which is why it stood out.

In minimal it's now a bare glyph (19pt regular, 34pt hit area, no fill, no border), like the
Reminders toolbar. Same root cause and same fix in `AddReminderView`: `section(_:_:)` wrapped
every group in a bordered box, and squaring it produced a hard rectangle around each section.
In minimal the section is now a grey caps label with the rows underneath between two hairlines,
and the title field is text with a rule under it rather than a boxed input.

**General lesson: `Theme.radius(0)` is not enough for anything with a visible border.** Squaring
a bordered box makes it louder, not quieter. The container has to be removed, not reshaped.

### 5. Use Apple Reminders as the reference

The row was rebuilt to match it. Confirmed with Noah before building:

| Decision | Answer |
|---|---|
| Time position | **Second line**, next to the list name — not right-aligned on line 1 |
| Second-line content | List + time. **Time only when due today; date + time otherwise** |
| Divider | **Inset to the text, subtle** (system separator colour) |

`ReminderCardView.minimalBody` is now:

```
○  Make a daily morning and evening checklist
   and paper calendar (physical)
   Personal  7:50            ← 7:50 red because overdue
   ─────────────────────────  ← rule starts under the title, not the circle
```

- Title wraps across the **full width** — no right-hand column stealing space. This is what
  fixes the squeezed titles in Noah's real data.
- Second line is **list + time only**. Repeat cadence, subtask counts, location, link, photo
  and source badge are gone from the list view and live in the reminder when you open it.
  Cramping them in is what produced the truncated `"Personal · Every 2 days ·…"`.
- **`minimalTimeLabel(_:)`** derives the date part from the reminder's own due date, not from
  which tab is on screen: due today → `"20:00"`, anything else → `"9 May, 09:00"`. That gives
  Noah exactly what he asked for (time on Today, date + time on Overdue) with **no tab
  plumbing**, and it stays correct on Home and Search where both kinds of row mix.
- Only the time takes the overdue colour, not the list name — it's built as two `Text`s rather
  than one interpolated string.

### Also flattened while in there

`nextUpCard` on Home was the last filled box left — a squared grey block sitting above a
cardless list. It's now a plain row with a rule under it, so Home reads as one list from the top.

## Files changed

- `AppSettings.swift` — `effectiveBoldText`, `applyWindowAppearance()`, `import UIKit`.
- `NudgeApp.swift` — root uses `effectiveBoldText`; calls `applyWindowAppearance()` at launch
  and on foreground.
- `Theme.swift` — `cardSurface` gains `dividerInset:`; new `minimalRowTextInset` constant;
  `rowVerticalPadding` 13 → 10; removed the unused `cardBorderWidth`.
- `ReminderCardView.swift` — `minimalBody` rebuilt to the Apple layout; `minimalMetaLine`
  replaced by `minimalListName` + `minimalTimeLabel`.
- `ContentView.swift` — `iconButton` bare in minimal; `nextUpCard` flattened.
- `AddReminderView.swift` — `section(_:_:)` and the title field unboxed in minimal.
- `SyncSettingsView.swift` — Bold text disabled in minimal; footer copy updated.

## Still not done — be honest about these

1. **Never compiled.** No Swift toolchain in Cowork. Brace/paren balance scripted and clean
   across every file, which is not a build.
2. **Sheets are only partly minimal.** `AddReminderView`'s sections and title field are fixed,
   but Reschedule, Bulk Move, Triage, Clean Up and the various review sheets were **not**
   individually rebuilt. They inherit minimal colours and squared corners, so any of them with
   a bordered container will have the same hard-outline problem the New Reminder sheet had.
   Expect Noah to flag one.
3. **Capsule chips still exist in sheets.** `Capsule()` isn't affected by `Theme.radius`.
   AddReminderView's time presets are the visible ones.
4. **The FAB is unchanged** — still a filled circle bottom-right. Apple uses a "＋ New Reminder"
   text button bottom-left. Not asked for; flag it and ask.
5. **Settings is still a system `Form`.** It now follows dark mode correctly, but its structure
   wasn't rebuilt.

## Test checklist

- [ ] Builds for iOS and macOS.
- [ ] **Minimal OFF looks completely unchanged.** Main regression risk — `iconButton`,
      `nextUpCard` and `AddReminderView.section` all got restructured with an `if` rather than
      edited in place, so verify the tinted path pixel-for-pixel.
- [ ] Settings sheet is **dark** in minimal + iOS Dark Mode. Open it, close it, switch iOS
      appearance while the app is open, reopen. Also check Clean Up and Dedup, which are sheets
      presented *from* Settings.
- [ ] Toggle Minimal off → Settings and the app go light (tinted themes pin `.light`, correctly).
- [ ] Bold text toggle is dimmed and does nothing in minimal; still works with Minimal off.
- [ ] Rows: rule starts under the title, not under the circle, and lines up with the title's
      left edge on every row.
- [ ] A long title (use "Make a daily morning and evening check list…") wraps full width and
      isn't squeezed.
- [ ] Today tab shows `"20:00"`; Overdue tab shows `"9 May, 09:00"`; overdue time is red and
      the list name next to it is **not**.
- [ ] Header icons are bare glyphs, no square outlines.
- [ ] New Reminder sheet: no rectangles around WHEN / the title field.
- [ ] Next up on Home is a row, not a box.
