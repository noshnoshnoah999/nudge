# Handoff — Minimal Light/Dark switch (31 Jul 2026, session E)

**Status:** written in Cowork, **not built, not committed.** Small change; needs Claude Code to
build, verify, commit, push.

Follows `HANDOFF_2026-07-31d_minimal-apple-grouped.md`. Noah's report: *"it looks great, but I
turned Minimal off then back on and it's now stuck in light mode — add a toggle so I can pick
light or dark when Minimal is on."*

## The bug, and why the fix is to delete the feature that caused it

Minimal originally returned **nil** from `AppSettings.colorScheme` so iOS would decide
light/dark automatically. That was Noah's own first choice and it's a nice idea, but nil means
*"no preference"*, and **nil does not reliably clear an override that a previous state already
set**. The eight tinted themes pin `.light`, so the sequence *tinted → minimal* leaves a stale
light override behind.

This bug has now been reported twice, escalating:

1. Session C: Settings rendered white while the rest of the app was dark (the stale override
   survived on sheets, which take their style from the presenting window).
2. Session E (this one): toggling Minimal off and on again left the **whole app** stuck light.

Session C's fix wrote `.unspecified` to every window to clear it. That fixed the sheet case and
not this one — which strongly suggests SwiftUI applies `preferredColorScheme` at the
**hosting-controller** level, where a window-level write is shadowed. I'm not certain of that
mechanism, and it no longer matters, because:

**`colorScheme` now never returns nil.** Minimal carries its own explicit `minimalDark`
preference and the property always returns a concrete `.light` or `.dark`. There is no "clear"
operation left to fail, so the entire class of bug is gone.

**Cost, stated plainly:** minimal no longer follows iOS automatically. It will not flip itself
at sunset. That's a deliberate trade of one feature for one class of bug, and it's what Noah
asked for. If he wants "Match iOS" back as a third option, it has to resolve to a concrete
value (reading the true system style from a trait collection the app hasn't overridden) rather
than passing nil — say so before building it.

## What changed

- **`AppSettings.minimalDark`** — new `@Published Bool`, default **true** (minimal was built and
  reviewed in dark, and the Apple Reminders reference is dark).
  **DEVICE-LOCAL, not synced.** Two reasons: the MacBook lives in a bright room and the iPhone
  gets used at night, so this is genuinely per-device; and it avoids growing
  `applyLocalAppearance` / `seedAppearanceIfMissing` / `cloudAppearance` / `onCloudAppearance`
  a fifth parameter for the third time. **If Noah wants it synced, say so — it's a real
  decision, not an oversight.**
- **`AppSettings.effectiveStyle`** — one private source of truth (`UIUserInterfaceStyle`) feeding
  both `colorScheme` and `applyWindowAppearance()`, so the SwiftUI and UIKit paths cannot
  disagree. Non-minimal is always `.light`.
- **`applyWindowAppearance()`** now writes a concrete style rather than `.unspecified`. It's
  belt-and-braces at this point — `preferredColorScheme` should be sufficient now that it's
  never nil — but it costs nothing and covers windows SwiftUI doesn't own (alerts, and the
  separate Mac windows on Catalyst).
- **Settings** — a segmented `Light / Dark` picker directly under the Minimal toggle, shown only
  when Minimal is on. Footer copy updated to say it's per-device.
- **Changelog 2.30** — the dark-mode line rewritten; it no longer claims Nudge follows the
  phone's setting.

## Test checklist

- [ ] Builds for iOS and macOS.
- [ ] **The exact reported repro:** Minimal on → off → on. It must come back in whatever
      Light/Dark it was, not stuck light.
- [ ] Switch Light ↔ Dark with Settings open — the sheet itself should change immediately, not
      just the screen behind it.
- [ ] Open Settings, close, reopen after switching. Then Clean Up and Dedup (sheets presented
      *from* Settings), which is where the stale override first showed up.
- [ ] Minimal off → app is light on every screen, exactly as before. The tinted themes are
      unchanged by this session.
- [ ] Set iPhone dark and MacBook light and confirm they stay independent (this pref does not
      sync — that's intended, flag it if Noah expected otherwise).
- [ ] Minimal **light** mode is still worth a proper look — session D changed
      `Theme.surface` to `secondarySystemBackground`, and if the cards read as muddy against
      `systemBackground` in light, the fix is `systemGroupedBackground` for the page.
