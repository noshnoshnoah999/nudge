# Claude Code prompt — Today widget background, tinted-mode fix attempt 2 (2026-07-25b)

Cowork wrote source edits but cannot build, test, commit, or push in this repo.

## Context — read this before touching anything

Read `HANDOFF_2026-07-25b_widget-background-tinted-mode.md` first.

The previous attempt (commits `7073500`, `88c1a88`) **failed on device** even after a
clean install and removing/re-adding the widget. Pixel analysis of Noah's Home Screen
screenshots in Apple tinted mode showed:

- Wallpaper: `#000000`
- Third-party dumb-phone launcher widget card: `#000000` (invisible — what we want)
- Nudge Today widget card: **`#181818`** despite True Black being selected

Corrected diagnosis: `containerBackgroundRemovable(false)` DOES preserve the background
layer, but a flat SwiftUI `Color` inside it still gets remapped by the system in
`.accented` mode. `Image` has an opt-out that `Color` doesn't:
`.widgetAccentedRenderingMode(.fullColor)`.

So the fix now renders the background as a **generated solid-colour Image** instead of a
`Color`. No screenshot / App Group / Supabase upload needed, because Noah's wallpaper
measures a genuinely flat `#000000`.

Files edited (uncommitted):
- `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`

## What to do

1. `git diff` and review before anything else.

2. Build the `NudgeWidgets` extension target and the main app. Watch for:
   - `UIGraphicsImageRenderer` / `UIColor` availability inside the widget extension (UIKit is imported behind `canImport(UIKit)`).
   - `widgetAccentedRenderingMode(.fullColor)` — `Image` modifier, iOS 18+. Project targets iOS 26.5, so fine, but confirm it resolves.
   - The view-builder form `containerBackground(for: .widget) { ... }` in `TodayWidget` — previously the ShapeStyle form was used.
   - `Rectangle().fill(.background)` in `TodayWidgetBackground`.
   - `TodayStyle.background` replaced `TodayStyle.backgroundColor` as the stored property; make sure nothing else still assigns the old one.

3. **Install on Noah's iPhone and test in Apple tinted Home Screen mode.** A clean build
   is NOT sufficient — the last attempt compiled fine and still failed.
   - Set the widget's Background to **True Black**.
   - Take a Home Screen screenshot and check the card interior colour against the wallpaper. Target: both `#000000`, i.e. the card is invisible. Anything around `#181818` means it failed again.
   - Also verify **Soft Black** gives `#0B0B0B`.
   - Verify **System Default** still looks normal.
   - Verify reminder titles are still legible (they measured `#4E4E4E` before; the background is now darker than the system's substitute, so re-check contrast).
   - Re-check normal (non-tinted) Home Screen mode still works.
   - Remove and re-add the widget if the new option doesn't appear in Edit mode.

4. **If it still renders `#181818`**, work down the fallback chain in the handoff:
   first move the background from `containerBackground` to widget **content** with
   `.contentMarginsDisabled()` + a `ZStack` + `.containerBackground(.clear, for: .widget)`.
   Report which step was needed.

5. Confirm the other widgets are visually unchanged: Overdue, Progress, QuickAdd, Lock
   Screen quick-add. Scope is the Today widget only.

6. Commit, e.g.
   `fix(widget): render Today background as fullColor image so it survives tinted mode`

7. Push to `origin/main`.

8. **After committing and pushing, remove any locks or stale locks** (`.git/index.lock`,
   leftover Xcode DerivedData locks) so the next session starts clean.

## Safety notes

- No secrets or API keys involved; don't add any.
- Widget UI/config only — no data model, auth, or sync changes.
- Do **not** implement the Supabase-screenshot-upload fallback without asking Noah first — it would put a Home Screen screenshot in cloud storage, and it shouldn't be needed since his wallpaper is flat.

## Report back

State plainly: the measured hex of the card interior vs the wallpaper after the change,
and whether the primary fix or a fallback step was required. Those numbers are the
pass/fail criterion — not "it looks black".
