# Claude Code prompt — Minimal design (31 Jul 2026, session B)

Paste everything below the line into Claude Code in the Nudge repo.

---

Read `HANDOFF_2026-07-31b_minimal-design.md` in the repo root first. Do not re-plan the
feature — it's written and the design decisions were confirmed with Noah. Your job is to build
it, fix compile errors, verify on device, then commit and push.

## Context

Commit `85cc7f0` ("Add Plain and Plain Dark themes") shipped and **Noah rejected it on device**.
It treated "minimal" as a colour palette, so cards kept their fill and border and were merely
squared off and greyed out — a washed-out Nudge rather than a minimal app.

This change removes those two palettes and replaces them with the real thing: a **"Minimal
design" switch** that renders design 1 from the old `DesignGalleryView` preview — a flat list
with no cards at all, circle · title · right-aligned time, hairline rules between rows.

**Minimal is a layout, not a palette.** If you find yourself keeping a fill or a border while
changing a colour, that's the bug that got rejected last time.

Dark mode: `AppSettings.colorScheme` returns **nil** in minimal, handing light/dark to iOS, and
every minimal colour is a semantic `UIColor` that resolves per appearance. There is deliberately
no in-app light/dark picker. Do not add one.

## Step 1 — build

Build the Nudge scheme for iOS and macOS (Mac Catalyst). Fix compile errors.

Most likely sources:

1. **`DesignGalleryView.swift` was deleted.** Its only reference (a NavigationLink in
   `SyncSettingsView`) was removed too. `Nudge/` is a synchronized group so no `project.pbxproj`
   edit should be needed — this was checked, the file had 0 pbxproj references — but confirm
   the target builds without it and that Xcode hasn't left a dangling reference.
2. **Sync signature changes.** `applyLocalAppearance`, `seedAppearanceIfMissing`,
   `cloudAppearance` and `onCloudAppearance` all gained a `minimalDesign` parameter. If
   anything still calls the 3-argument versions, update the caller.
3. **`Palette` lost `isDark` and `minimal`.** Anything still reading them is leftover from
   `85cc7f0` and should be deleted, not restored.
4. **`cardSurface(...)` gained `showsDivider:` and `emphasis:`** (both defaulted).

`Color(.systemBackground)` / `Color(.label)` etc. in `Theme.swift` compile under `import
SwiftUI` alone on iOS — the deleted `DesignGalleryView` used the same pattern. If Catalyst
complains, add `import UIKit`.

## Step 2 — verify on device

Work the checklist at the bottom of the handoff. In priority order:

1. **Minimal off must look exactly like today.** The 8 tinted themes are the main regression
   risk, because `Theme`'s colour accessors were all rewritten to branch.
2. **Minimal on, Light mode — compare against the screenshot Noah sent** (the "1 · Minimal"
   preview). No cards, no borders, no shadows. If you can still see a box around a reminder,
   something is wrong and it's the thing that got rejected before.
3. **Minimal on, Dark mode.** Toggle Dark Mode in iOS Settings. The whole app, keyboard, sheets
   and pickers should go black. Then hunt white-on-white: in minimal dark the accent is WHITE,
   so any surviving hardcoded `.white` label sat on an accent fill is invisible. Fix any you
   find with `Theme.onAccent` (accent fills), `Theme.onCoral` (red fills) or `Theme.onTextMain`
   (the toast/selection bars, which fill with `Theme.textMain`).
4. **Migration off the dead palette.** Commit `85cc7f0` is already on Noah's iPhone and MacBook,
   so the cloud settings row may currently hold `theme = "plain"` or `"plainDark"`. Both `init`
   and `applyFromCloud` translate that to Mocha + Minimal on. Verify a device that was on Plain
   comes up on Minimal and does **not** push the dead id back to the cloud.
5. **Sheets.** The handoff is honest that Add Reminder / Reschedule / Bulk Move / Triage inherit
   minimal colours and squared corners but were **not** rebuilt as hairline lists. Look at them
   and tell Noah how card-like they still are — that's the next decision, not a bug to fix now.

## Step 3 — commit and push

Only after a clean build and eyeballing minimal light, minimal dark, and at least two tinted
themes on device.

```
git add -A
git commit -m "Replace Plain palettes with a real Minimal design switch

85cc7f0 shipped minimal as two colour palettes, which kept Nudge's card
structure and only squared it off. Rejected on device. Minimal is a layout,
not a palette.

- Remove the plain/plainDark palettes and Palette.isDark/.minimal
- Add AppSettings.minimalDesign, synced alongside theme/boldText/compact
- Theme colours return UIKit semantic colours in minimal, so the eight
  palettes are ignored and the app follows iOS Light/Dark for free
  (colorScheme returns nil); no in-app dark picker
- cardSurface in minimal draws NO fill and NO border, just a hairline under
  the row plus a leading bar for selection
- ReminderCardView gets a dedicated minimalBody: circle, title, right-aligned
  time, with all chips collapsed into one grey meta line; Ask Claude kept as
  plain text
- Drop the progress hero, section count pills and the group's orange wrapper
  box in minimal; indent expanded group members instead
- Migrate anyone left on the dead plain/plainDark theme id to Mocha + minimal,
  on launch and on cloud apply, so the dead id can't be pushed back up
- Delete DesignGalleryView and the Preview designs (beta) settings link
- Changelog 2.30 rewritten
"
git push
```

## Step 4 — clean up locks

After the push, remove any git locks or stale locks left behind (`.git/index.lock`,
`.git/HEAD.lock`, `.git/refs/**/*.lock`) so the next session starts clean. Confirm `git status`
is clean and no lock files remain before finishing.

## Report back

Whether it built, what you fixed, how minimal looks against the screenshot in both light and
dark, and how card-like the sheets still are.
