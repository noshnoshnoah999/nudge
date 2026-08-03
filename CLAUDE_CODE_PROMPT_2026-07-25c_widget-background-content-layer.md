# Claude Code prompt — Today widget: content-layer background + custom screenshot (2026-07-25c)

Cowork wrote the source but cannot build, test, commit, push, or edit the Xcode project.

## Context — read first

Read `HANDOFF_2026-07-25c_widget-background-content-layer.md`.

Three previous attempts failed **on device**, verified by pixel-sampling Home Screen
screenshots in Apple tinted mode (wallpaper `#000000`, Nudge card stayed `#181818`):

- `7073500` `containerBackground(Color)` → `#181818`
- `88c1a88` + `containerBackgroundRemovable(false)` → `#181818`
- `87c16d4` + `Image` with `.widgetAccentedRenderingMode(.fullColor)` → `#181818`

So the system overrides the **container background layer** whatever is in it. This pass does
two things: moves the background to the **content layer**, and adds a **custom screenshot**
option stored on-device only.

## Files

**New files — XCODE PROJECT REGISTRATION IS ALREADY DONE. Do not repeat it.**

- `ios/Nudge/Shared/WidgetBackgroundImageStore.swift` — **already registered in BOTH targets.**
  `Shared/` is a plain `PBXGroup` with explicit children, so this needed manual pbxproj
  registration. Done by mirroring `AuthStore.swift` (which has identical membership):
  1 `PBXFileReference` (`2816A8E60E576643D217AC45`), 2 `PBXBuildFile` entries
  (`139148C841C436AA3B6BEA32`, `FBAD338765DC3F467444910E`), 1 entry in the `Shared` group's
  children, and 1 entry in each Sources phase — app `3A9BD1EC2FCE10E000E88354` and
  `NudgeWidgets` `6E30D814772B63ABFE4EC75A`. Verified: no duplicate object IDs, balanced
  braces/parens, exactly one entry per phase.
- `ios/Nudge/Nudge/WidgetBackgroundView.swift` — **needs nothing.** The `Nudge/` folder is a
  `PBXFileSystemSynchronizedRootGroup` (objectVersion 77) owned by the app target, so files
  added there are members automatically. This is also why no other app view appears in the
  pbxproj. Do **not** add an explicit reference for it — that would duplicate membership.

A backup of the pre-edit pbxproj is at `/tmp/pbxproj.backup` in the Cowork sandbox, which will
not survive the session. The change is a 6-line insertion visible in `git diff`, so revert via
git if it causes trouble.

Note: `gem install xcodeproj` is blocked by network policy in the Cowork sandbox, which is why
this was done as a verified text edit rather than with the existing `add_widget_files.rb`.
That script is still the better tool if you have the gem available locally.

**Modified (uncommitted):**
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`
- `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
- `ios/Nudge/Nudge/SyncSettingsView.swift`

## What to do

1. `git diff` and review — including the 6-line `project.pbxproj` change.

2. Build the `NudgeWidgets` extension and the main app (project registration is already done —
   see above). Watch for:
   - `.contentMarginsDisabled()` resolving on `AppIntentConfiguration` at the iOS 26.5 target.
   - `containerBackgroundRemovable(false)` is **removed** — confirm nothing still references it.
   - `.widgetAccentedRenderingMode()` is an **`Image`** modifier and must come before
     `.aspectRatio` / `.clipped`. It's written that way deliberately; don't "tidy" it into a
     shared modifier chain or it won't compile.
   - `WidgetBackgroundImageStore` is reachable from the widget target (see membership above).
   - `Theme.surface` / `Theme.bg` exist and are accessible from `WidgetBackgroundView`.
   - New `.customPhoto` enum case — confirm every `switch` over `WidgetBackground` is exhaustive.

3. **Install on Noah's iPhone and MEASURE. Do not eyeball it** — a clean build has passed three
   times while the bug survived.

   **Part A — flat preset, tinted mode:**
   - Apple **tinted** Home Screen mode, widget Background = **True Black**.
   - Screenshot the Home Screen and sample pixels: card interior vs wallpaper.
     **Pass = both `#000000`. Anything near `#181818` = failed again.**
   - Repeat for **Soft Black** → expect `#0B0B0B`.
   - **System Default** must look exactly as before.
   - Check for a grey hairline at the rounded corners.
   - Check reminder titles are still legible.
   - Check row count — `TodayWidgetView.maxRows` uses hardcoded height estimates (320 large /
     130 medium) that assumed WidgetKit's content margins; re-tune if a row is lost or spills.
   - Re-test normal (non-tinted) mode.

   **Part B — custom screenshot:**
   - App → Settings → **Widget Background** → pick a screenshot of an empty Home Screen page.
   - Confirm the preview appears and the save alert shows.
   - Long-press widget → Edit Widget → Background → **"My Wallpaper Screenshot"**.
   - Confirm the widget renders that image and blends.
   - Confirm **Remove image** works and the widget falls back cleanly.
   - Confirm selecting "My Wallpaper Screenshot" with **no image stored** falls back to the
     normal background rather than rendering blank/black-on-nothing.
   - Sanity-check the Keychain path works from the widget **while the device is locked**
     (the item uses `kSecAttrAccessibleAfterFirstUnlock`) — lock the phone, wait for a widget
     refresh, confirm the background is still there.

4. **If Part A still measures `#181818`, STOP and report.** Do not invent a fourth theory. It
   would mean content is being tinted too, and the screenshot option would fail for the same
   reason.

5. Confirm Overdue, Progress, QuickAdd and the Lock Screen quick-add are visually unchanged.

6. Commit — two logical commits is cleaner:
   - `fix(widget): draw Today background in content layer so tinted mode can't override it`
   - `feat(widget): custom wallpaper-screenshot background, stored on-device via shared Keychain`

7. Push to `origin/main`.

8. **After committing and pushing, remove any locks or stale locks** (`.git/index.lock`,
   leftover Xcode DerivedData locks) so the next session starts clean.

## Safety notes

- **The screenshot must never leave the device.** No Supabase upload, no CloudKit, no sync to
  the MacBook — Noah required this explicitly. The Keychain item is local-only; do not add
  `kSecAttrSynchronizable`.
- No secrets or API keys; don't add any.
- The 256 KB cap and downscaling in `WidgetBackgroundImageStore` are deliberate guard rails
  against wedging large blobs into the Keychain. Don't raise the cap to make a photo fit —
  the correct answer is for the user to pick a screenshot.
- No data model, auth, or sync logic changed.

## Report back

Give the measured hex of the card interior vs the wallpaper for True Black in tinted mode, and
whether the custom screenshot option worked. Those numbers are the criterion — not
"looks black to me".
