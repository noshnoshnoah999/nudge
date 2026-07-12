# Bold Text Feature — Handoff (2026-07-12)

## What was added
A user-toggleable "Bold Text" setting that renders app text at bold weight. iOS + macOS (Catalyst) only. Web page untouched.

## Files changed (3)
1. **`ios/Nudge/Nudge/AppSettings.swift`**
   - New `@Published var boldText: Bool`, persisted to `UserDefaults` key `pref.boldText`.
   - Added `K.boldText` key and init load (`bool(forKey:)`, defaults to `false`).

2. **`ios/Nudge/Nudge/SyncSettingsView.swift`**
   - New `Toggle("Bold text", ...)` in the Appearance section, between "Compact list" and "Sound & haptics".
   - Footer text updated to mention it.

3. **`ios/Nudge/Nudge/NudgeApp.swift`**
   - At the `RootContainer()`, added `.environment(\.font, settings.boldText ? .body.weight(.bold) : nil)`.
   - When off, passes `nil` so default rendering is completely unchanged.

## How it works
The root-level `.environment(\.font, ...)` sets the default font for all descendant `Text` that don't specify their own font. Toggle is live (AppSettings is `@Published`, observed app-wide), no restart needed.

## Known limitation (agreed with Noah: root pass first, spot-fix later)
This does NOT force-bold text that sets an explicit font/weight (e.g. `.font(.title.weight(.semibold))`, custom-styled buttons, some headers). Those keep their own weight and ignore the environment font. Expected coverage: most body text bold immediately; a minority of explicitly-styled elements need per-view follow-up.

### Follow-up if Noah wants "truly everything"
Audit views using `.font(...)` with explicit weights and gate them on `settings.boldText` (e.g. `.fontWeight(settings.boldText ? .bold : nil)`). Candidates to check first: TodayView, ReminderCardView, GroupCardView, section headers.

## Verification status
- NOT compiled — Cowork sandbox has no Swift/Xcode toolchain.
- Edits are internally consistent (pref declared/persisted/keyed/initialized/bound/applied — 6 references line up).
- **Build + visual check must happen in Xcode on the Mac.** Toggle on/off, confirm body text bolds and un-bolds, confirm nothing breaks layout.

## Safety
No secrets, keys, network, or data-model changes. Pure UI/preference. Low risk.
