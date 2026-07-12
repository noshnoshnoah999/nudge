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
   - At the `RootContainer()`, added `.fontWeight(settings.boldText ? .bold : nil)`.
   - When off, passes `nil` so default rendering is completely unchanged.
   - NOTE: first attempt used `.environment(\.font, ...)` — that barely bolded anything because
     it only affects text with no font of its own, and Nudge sets `.font(...)` almost everywhere
     (~270 sites). Switched to a root `.fontWeight()`, which overrides weight even when a view
     sets its own `.font(.headline)` etc. Requires iOS 16+ (deployment target is 26.5, fine).

## How it works
A root-level `.fontWeight(.bold)` overrides the weight of all descendant text, because weight
is a separate modifier from font. This catches every `.font(...)` call that doesn't pin its own
weight (~200 of the ~270). Toggle is live (AppSettings is `@Published`), no restart.

## Known limitation (Noah chose: ship root fix, test first)
~71 text elements set an EXPLICIT weight and will resist the root override:
- 46 `.semibold`, 13 `.medium` — already heavyish, mostly won't look wrong.
- 7 `.light`, 5 `.regular` — these will look noticeably not-bold if the user hunts for them.
- (78 `.bold` + 3 `.heavy` are already bold — no action needed.)

### Follow-up if the stragglers bother Noah after testing
Make explicit weights conditional: `.fontWeight(settings.boldText ? .bold : .semibold)` at each
site. Grep for `weight(` / `.fontWeight(` / `.bold()` across `Nudge/`. Prioritise the ~12
`.regular`/`.light` sites first — those are the visible ones. Semibold/medium are optional.

## Verification status
- NOT compiled — Cowork sandbox has no Swift/Xcode toolchain.
- Edits are internally consistent (pref declared/persisted/keyed/initialized/bound/applied — 6 references line up).
- **Build + visual check must happen in Xcode on the Mac.** Toggle on/off, confirm body text bolds and un-bolds, confirm nothing breaks layout.

## Safety
No secrets, keys, network, or data-model changes. Pure UI/preference. Low risk.
