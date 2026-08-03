# Handoff — Today widget background: making it survive Apple tinted mode (2026-07-25b)

Follow-up to `HANDOFF_2026-07-25_widget-background-colour.md`. That session's fix
(`containerBackgroundRemovable(false)`, commits `7073500` + `88c1a88`) was built,
installed, and the widget was removed and re-added — **and it still did not work.**
This doc records what was actually measured and what changed as a result.

## Measured evidence (not inferred)

Two Home Screen screenshots from Noah's iPhone, both in Apple **tinted** mode,
analysed pixel-by-pixel:

| Region | Third-party dumb-phone launcher widget | Nudge Today widget |
|---|---|---|
| Wallpaper, outside the widget | `#000000` | `#000000` |
| Card interior | `#000000` (identical → invisible) | **`#181818`** |

So with **True Black selected** and `containerBackgroundRemovable(false)` **already
live on device**, the Nudge card still rendered `#181818` (rgb 24,24,24) — iOS's dark
elevated material — against a pure-black wallpaper. That's the visible grey panel
Noah was complaining about.

## Corrected root cause

Two separate things were being stripped, and the previous session only fixed one:

1. **The background layer** — in `.accented` (tinted Home Screen) mode the system
   discards `containerBackground` entirely. `containerBackgroundRemovable(false)`
   fixes this, and it did work: the layer was preserved.
2. **The colour inside that layer** — a flat SwiftUI `Color` is still remapped by the
   system to its own material. This is what was left broken, and it's why the card
   measured `#181818` instead of `#000000`.

**The asymmetry that solves it:** `Image` has an opt-out that `Color` does not —
`.widgetAccentedRenderingMode(.fullColor)` (iOS 18+) renders an image in its original
colours with no tint treatment. There is no `Color` equivalent.

This is also, mechanically, what third-party "transparent widget" apps do: they have
the user attach a screenshot of an empty Home Screen page and draw it as a background
**image**. Noah confirmed this is exactly how he made the launcher blend.

**Key realisation that avoids a lot of work:** Noah's wallpaper measures a genuinely
flat `#000000`. A screenshot of a flat wallpaper is pixel-identical to a generated
flat image. So Nudge does **not** need a real screenshot — and therefore does not need
an App Group (unavailable on a free Apple team), a Supabase upload, or a photo picker.
Generate the solid-colour image in code.

## What changed

- `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
  - `import UIKit` (guarded by `canImport`).
  - `WidgetBackground.solidImage` — returns a cached 32×32 opaque solid-colour `UIImage`
    per preset, built with `UIGraphicsImageRenderer` (`format.opaque = true`, so there's
    no alpha channel for the system to luminance-map).
  - `TodayStyle` now carries `background: WidgetBackground` (the enum) rather than a
    resolved `Color?`, because the view needs to render the *image* form.
    `backgroundColor` kept as a computed convenience.
  - New `TodayWidgetBackground` view: renders `Image(uiImage:).resizable()
    .widgetAccentedRenderingMode(.fullColor)` for the near-black presets, and
    `Rectangle().fill(.background)` for System Default.
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`
  - `TodayWidget` now uses the **view-builder** form of `containerBackground(for:)` with
    `TodayWidgetBackground(...)`, replacing the `AnyShapeStyle`/`Color` form.
  - `containerBackgroundRemovable(false)` **kept** — it's still needed to preserve the
    layer. Comment rewritten to record that it is necessary but not sufficient.

## Why both pieces are needed

- `containerBackgroundRemovable(false)` → keeps the background layer from being stripped.
- `Image` + `.widgetAccentedRenderingMode(.fullColor)` → keeps the colour from being remapped.

Remove either and the grey card comes back.

## Fallback chain if this still fails

Try in order, and record which one worked:

1. **Content instead of container background.** Add `.contentMarginsDisabled()` to
   `TodayWidget`, wrap `TodayWidgetView` in a `ZStack` with `TodayWidgetBackground` as
   the bottom layer filling the bounds, and set `.containerBackground(.clear, for: .widget)`.
   Content is not stripped in `.accented` mode the way `containerBackground` is. Padding
   that content margins were providing must be restored by hand.
2. **Real screenshot instead of a generated image.** Only if Noah's wallpaper turns out
   not to be flat (it measures flat today, so this is unlikely). Needs a delivery path,
   because App Groups are unavailable on a free Apple team: either an `IntentFile`
   photo-picker `@Parameter` on `TodayWidgetConfigIntent` (unverified whether iOS renders
   a picker for this in widget Edit mode) or upload via Supabase Storage, which the widget
   already has working network + auth for. **Flag the privacy trade-off before uploading
   any Home Screen screenshot to Supabase.**

## Open risk

`containerBackgroundRemovable(false)` has a reported side effect (Apple Developer Forums
768862) where content gets pulled into the tint treatment even when marked
non-accentable. Noah's titles currently render `#4E4E4E` and are legible, so this has
not bitten — but re-check legibility after this change, since the background is now
darker than what the system was substituting.

## Status

Source written in Cowork; **not built, not tested, not committed** — Cowork cannot build
iOS or commit in this repo. See `CLAUDE_CODE_PROMPT_2026-07-25b_widget-background-tinted-mode.md`.

## Sources

- [`widgetAccentedRenderingMode(_:)`](https://developer.apple.com/documentation/swiftui/image/widgetaccentedrenderingmode(_:))
- [`containerBackgroundRemovable(_:)`](https://developer.apple.com/documentation/swiftui/widgetconfiguration/containerbackgroundremovable(_:))
- [Adapting widgets for tint mode and dark mode in SwiftUI](https://www.createwithswift.com/adapting-widgets-for-tint-mode-and-dark-mode-in-swiftui/)
- [How to support tinted home screen widgets in iOS 18](https://nemecek.be/blog/206/how-to-support-tinted-home-screen-widgets-in-ios-18)
- [Apple Developer Forums 757231 — containerBackground stripped in tinted mode](https://developer.apple.com/forums/thread/757231)
- [Apple Developer Forums 768862 — removable(false) tint side effects](https://developer.apple.com/forums/thread/768862)
- [WidgetClub — how transparent-widget apps use a wallpaper screenshot](https://widget-club.com/article/wigets-transparent)
