# Handoff — Today Widget background colour + tinted-mode fix (2026-07-25)

## Part 1 — Background colour picker

Added a background colour option to the Today widget's native Edit-mode config
(same pattern as the existing font/size/spacing/grayscale controls), so the
widget can blend into Noah's near-black Lock/Home Screen wallpapers instead of
showing the default light-adaptive widget card.

Two presets, sampled directly from Noah's device (iOS colour picker, sRGB hex):
- **Soft Black** — `#0B0B0B` (lighter of his two wallpapers)
- **True Black** — `#000000` (his main/default wallpaper)
- **System Default** — unchanged `.background` material (still the default)

## Part 2 — Why it didn't work in Apple's "tinted" mode (the real bug)

Noah reported: the picker works in normal (full-colour) Home Screen mode, but in
Apple's **tinted** mode the Nudge widget still renders as a grey card — while a
third-party "dumb phone" app-launcher widget on the same screen renders true
black. He wants tinted mode specifically, because that's what makes his app
icons monochrome.

**Cause (verified against Apple docs + dev forums, not guessed):**

- Tinted Home Screen mode renders widgets in `WidgetRenderingMode.accented`.
  (Note: `.vibrant` is Lock Screen, NOT tinted Home Screen — easy to conflate.)
- In `.accented` mode the system **discards `containerBackground` by default** and
  substitutes its own translucent grey material. So our chosen `#000000` was
  being thrown away before it ever rendered. This is documented, intended
  WidgetKit behaviour — not a Nudge bug.
- The documented opt-out is **`.containerBackgroundRemovable(false)`** on the
  `WidgetConfiguration`. It tells the system the background is essential (Apple
  added it for widgets like Photos and Maps, which make no sense background-less).
  This is almost certainly what the dumb-phone launcher uses.

**Applied fix:** `.containerBackgroundRemovable(false)` added to `TodayWidget`.

### Two important caveats

1. **Cannot be conditional.** The modifier lives on `WidgetConfiguration`, not on
   the view, so it can't depend on which preset the user picked. Consequence:
   with "System Default" selected, tinted mode now preserves the `.background`
   material instead of the system's tinted material. Acceptable trade — the
   near-black presets are the whole point of the feature.

2. **Known Apple quirk — MUST be device-tested.** Dev forum thread 768862 reports
   that with `containerBackgroundRemovable(false)`, content gets pulled into the
   tint treatment even when marked non-accentable. Today's rows are plain
   `.secondary` text, so this is *expected* to be benign — but Noah's tint colour
   is near-black, so if titles take the tint they could render black-on-black and
   vanish entirely. This is the one thing that has to be checked on-device.

### Fallback if titles vanish in tinted mode

Don't use `containerBackground` for the colour at all. Instead:
- Remove `.containerBackgroundRemovable(false)`.
- Add `.contentMarginsDisabled()` to the `TodayWidget` configuration.
- Wrap `TodayWidgetView` in a `ZStack` with the chosen colour as the bottom layer
  (`style.backgroundColor`), filling the full widget bounds, and keep a minimal
  `.containerBackground(.clear, for: .widget)`.
- Re-add the padding the content margins were providing, manually.

Content is not stripped in `.accented` mode the way `containerBackground` is, so
the colour survives. This is the workaround referenced in forum thread 768862.
It's more code and needs padding re-tuned by hand, which is why it's the fallback
rather than the first attempt.

## Files touched

- `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
  - New `WidgetBackground: AppEnum` — `.systemDefault` / `.softBlack` / `.trueBlack`, each mapping to a `Color?` (`nil` = system default).
  - Added `@Parameter(title: "Background", default: .systemDefault) var background: WidgetBackground` to `TodayWidgetConfigIntent`.
  - Added `backgroundColor: Color?` to `TodayStyle`, populated in `init(_ c: TodayWidgetConfigIntent)`.
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`
  - `TodayWidget`'s `.containerBackground(...)` uses `e.style.backgroundColor` (via `AnyShapeStyle`), falling back to `.background`.
  - Added `.containerBackgroundRemovable(false)` with a full explanatory comment.

Only the Today widget (`systemMedium`/`systemLarge`) is affected — Overdue,
Progress, QuickAdd, and the Lock Screen widget are untouched, as scoped.

## Why (product rationale)

Noah runs a deliberately minimal, near-black Lock/Home Screen to reduce phone
engagement. He uses Apple's tinted mode specifically to strip colour from app
icons. The widget's system-substituted grey card broke that visual quiet by
standing out as an obvious panel. Matching the widget to the wallpaper makes it
recede. He switches between two wallpaper shades, hence a picker rather than a
hardcoded colour.

## Not done / follow-up

- No in-app settings mirror — Edit-mode only, per Noah's explicit choice.
- Curated presets, not a freeform colour picker — matches the existing Font/Spacing enum pattern.
- Nothing built or tested in this session (Cowork sandbox can't build iOS). Needs a Claude Code pass — see `CLAUDE_CODE_PROMPT_2026-07-25_widget-background-color.md`.
- Unverified: whether `containerBackgroundRemovable(false)` affects StandBy eligibility for this widget. Worth a glance during testing; low stakes since Noah's use case is Home Screen.

## Sources consulted

- Apple, "Bring widgets to new places" (WWDC23) — https://developer.apple.com/videos/play/wwdc2023/10027/
- `containerBackgroundRemovable(_:)` — https://developer.apple.com/documentation/swiftui/widgetconfiguration/containerbackgroundremovable(_:)
- "Adapting widgets for tint mode and dark mode in SwiftUI" — https://www.createwithswift.com/adapting-widgets-for-tint-mode-and-dark-mode-in-swiftui/
- "How to support tinted home screen widgets in iOS 18" — https://nemecek.be/blog/206/how-to-support-tinted-home-screen-widgets-in-ios-18
- Apple Developer Forums 757231 (containerBackground stripped in tinted mode) — https://developer.apple.com/forums/thread/757231
- Apple Developer Forums 768862 (removable(false) tint side effects + ZStack workaround) — https://developer.apple.com/forums/thread/768862
