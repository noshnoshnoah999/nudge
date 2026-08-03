# Handoff — Today widget background: content layer + custom screenshot (2026-07-25c)

Two changes in one pass:
- **A.** Move the widget background from `containerBackground` to the **content layer** (the
  actual tinted-mode fix).
- **B.** Add a **custom screenshot** background option, stored on-device only (Noah's request).

## A — Why the content layer

### What's been ruled out (all measured on-device, not theorised)

| # | Commit | Change | Result |
|---|---|---|---|
| 1 | `7073500` | `containerBackground(Color)` with `#000000` | card rendered **`#181818`** |
| 2 | `88c1a88` | + `containerBackgroundRemovable(false)` | still **`#181818`** |
| 3 | `87c16d4` | + `Image` with `.widgetAccentedRenderingMode(.fullColor)` | still **`#181818`** |

Measured from Home Screen screenshots in Apple tinted mode: wallpaper `#000000`, Nudge card
`#181818`, and a third-party dumb-phone launcher widget on the same screen at `#000000`
(invisible).

Attempt 3 is the decisive one — it disproves "a `Color` can't hold its colour but an `Image`
can", because an *image* in the container background was overridden too. The rule is:

> In `.accented` (tinted Home Screen) mode the system overrides the **container background
> layer** regardless of its contents, and regardless of `containerBackgroundRemovable`.

### The change

Draw the background as **widget content**, which is composited *above* the container
background and is not substituted.

- `NudgeWidgets.swift` → `TodayWidget` body is now a `ZStack`: `TodayWidgetBackground` at the
  bottom, `TodayWidgetView` above.
- `.contentMarginsDisabled()` added — **required**, or WidgetKit insets the content and the
  system grey shows as a border. Padding WidgetKit used to supply is now manual (16 h / 14 v).
- `.containerBackground(.background, for: .widget)` retained so "System Default" is untouched.
- **`containerBackgroundRemovable(false)` removed** — it never fixed the colour and carries a
  documented side effect (Apple Developer Forums 768862) pulling content into the tint
  treatment, a real black-on-black risk with Noah's near-black tint. Nothing depends on it now.

## B — Custom screenshot background

Noah's explicit request, and how he made the third-party launcher blend: attach a screenshot
of an empty Home Screen page and use it as the widget background.

**Constraint he set: the image stays local to the iPhone. No Supabase, no sync to the MacBook.**

App Groups are unavailable (free Apple team), so there is no shared file container or shared
UserDefaults. `IntentFile` as a widget-Edit-mode photo picker could **not** be verified to
work, so it was not used. Delivery is via the **shared Keychain access group**
(`FMF6YAVA23.uk.flouty.Nudge.shared`) — already proven in this project, it's how the widget
reads the Supabase session (`AuthStore.swift`).

### New files

- `ios/Nudge/Shared/WidgetBackgroundImageStore.swift` — save/load/clear the image as JPEG bytes
  in the shared Keychain. Downscales to a 1200 px longest edge, steps JPEG quality down
  (0.8 → 0.2) to fit, and hard-rejects anything over **256 KB** with a message telling the user
  to pick a screenshot rather than a photo. `kSecAttrAccessibleAfterFirstUnlock` so the widget
  can read it on a locked device, matching `AuthStore`.
- `ios/Nudge/Nudge/WidgetBackgroundView.swift` — the picker UI. `PhotosPicker` filtered to
  `.screenshots`, live preview, remove button, 4-step instructions, and an explicit note that
  the image is stored only on this iPhone. Calls
  `WidgetCenter.shared.reloadTimelines(ofKind: "NudgeToday")` after save/remove.

### Changed files

- `TodayWidgetStyle.swift` — `WidgetBackground` gains `.customPhoto`
  ("My Wallpaper Screenshot"); `solidImage` returns the stored image for that case;
  `TodayWidgetBackground` uses aspect-fill + clip for a real screenshot and plain stretch for
  the flat presets.
- `SyncSettingsView.swift` — new "Widget" section with a `NavigationLink` to
  `WidgetBackgroundView`, placed between the Upcoming and Overdue sections.

### Two-step UX (unavoidable)

Widget Edit mode can't show a photo picker, so setting this up is two places:
1. App → Settings → **Widget Background** → choose the screenshot.
2. Long-press widget → Edit Widget → **Background** → "My Wallpaper Screenshot".

If the option is selected but no image is stored, the widget falls back to its normal
background rather than rendering blank.

## Known limitations

- **Centred crop.** The screenshot is scaled to fill and centre-cropped; it is *not* aligned to
  where the widget actually sits on the Home Screen. Invisible on a flat wallpaper (Noah's
  case, measured `#000000`) but would misalign on a gradient or patterned one. Fixing properly
  would mean asking the user which grid position the widget occupies, or cropping in the app.
- **Keychain for image bytes** is not what the Keychain is for. It's bounded to 256 KB and the
  data is not secret, so the risk is wasted space rather than anything unsafe.
- **`maxRows` may need re-tuning.** `TodayWidgetView.maxRows` uses hardcoded usable-height
  estimates (320 large / 130 medium) that assumed WidgetKit's content margins. Manual padding
  is close but not identical.

## Watch for on test

- Grey hairline at the widget's rounded corners → content background isn't reaching the edges
  despite `.contentMarginsDisabled()`.
- Title legibility in tinted mode against a now-truly-black background.
- Row overflow / a missing row (see `maxRows` above).

## If the content layer ALSO gets overridden

Then tinted mode is tinting content too, and the screenshot option will fail for the same
reason — the photo was never the variable. Report the measured hex rather than iterating
blindly; that would be the fourth failed theory and it'd be time to reconsider whether this is
achievable at all in tinted mode.

## Xcode project registration — DONE

- `Shared/WidgetBackgroundImageStore.swift` is registered in **both** the app target and the
  `NudgeWidgets` extension target, mirroring `AuthStore.swift`. `Shared/` is a plain `PBXGroup`
  with explicit children, so this required a real pbxproj edit (6 lines).
- `Nudge/WidgetBackgroundView.swift` required **no** registration: `Nudge/` is a
  `PBXFileSystemSynchronizedRootGroup` (objectVersion 77) owned by the app target, so files
  dropped in that folder are members automatically. That's why no other app view appears in the
  pbxproj either. Adding an explicit reference would double up its membership — don't.

Useful thing learned: on this project, **new app-target files need no project edit at all**;
only `Shared/` and `NudgeWidgets/` files do.

## Status

Written in Cowork; project registration done and verified; **not built, not tested, not
committed.** See `CLAUDE_CODE_PROMPT_2026-07-25c_widget-background-content-layer.md`.
