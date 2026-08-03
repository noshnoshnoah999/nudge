# Claude Code prompt — Minimal Light/Dark switch (31 Jul 2026, session E)

Paste everything below the line into Claude Code in the Nudge repo.

---

Read `HANDOFF_2026-07-31e_minimal-light-dark-switch.md` first. Small change. Build, verify on
device, commit, push.

## Context

Noah turned Minimal off and back on and the app got **stuck in light mode**.

Root cause: minimal used to return **nil** from `AppSettings.colorScheme` so iOS would pick
light/dark. nil means "no preference", and it does **not** reliably clear an override a previous
state already set — and the eight tinted themes pin `.light`. So *tinted → minimal* left a stale
light override behind. This is the second report of the same root cause; session C saw it on
sheets only (white Settings page) and patched it by writing `.unspecified` to the windows, which
fixed that case and not this one.

**The fix removes the nil path entirely.** Minimal now has its own explicit `minimalDark`
preference, `colorScheme` always returns a concrete `.light`/`.dark`, and there is no "clear"
operation left to fail. Minimal no longer follows iOS automatically — that's the deliberate
trade, and it's what Noah asked for.

## Step 1 — build

Build for iOS and macOS (Mac Catalyst). Changes are confined to:

- `AppSettings.swift` — new `@Published var minimalDark` (device-local, `pref.minimalDark`,
  defaults **true**); new private `effectiveStyle: UIUserInterfaceStyle`; `colorScheme` and
  `applyWindowAppearance()` both derive from it.
- `SyncSettingsView.swift` — segmented Light/Dark picker under the Minimal toggle, shown only
  when Minimal is on; footer copy updated.
- `Changelog.swift` — 2.30 dark-mode line rewritten.

Note `minimalDark` is **not** in the Supabase sync bridge — deliberate, see the handoff. Don't
"fix" that by adding it.

## Step 2 — verify, and run the exact repro

The whole point of this change is one sequence, so test it first:

1. Minimal **on**, pick Dark.
2. Turn Minimal **off** (app goes light — correct, the palettes are light-backed tints).
3. Turn Minimal **back on**.
4. It must return to **Dark**, not stick in light.

Then:

- Flip Light ↔ Dark with Settings open. The sheet itself should change immediately, not just the
  screen behind it.
- Open Clean Up and Dedup from inside Settings — sheets presented *from* a sheet are where the
  stale override first surfaced in session C.
- Minimal off: every screen light, tinted themes exactly as before.
- iPhone dark + MacBook light stay independent (this pref doesn't sync, by design).

While you're on device, also look at **minimal light mode** properly — session D changed
`Theme.surface` to `secondarySystemBackground` and nobody has judged it in light yet. If the
cards read as muddy or invisible against `systemBackground`, report it; the fix would be
`systemGroupedBackground` for the page.

## Step 3 — commit and push

```
git add -A
git commit -m "Minimal: explicit Light/Dark switch instead of following iOS

Toggling Minimal off and back on left the app stuck in light mode. Minimal
returned nil from colorScheme so iOS would decide, but nil means 'no
preference' and does not reliably clear an override an earlier state set —
and the eight tinted themes pin .light. Same root cause as the white
Settings sheet in the previous round, which writing .unspecified to the
window only half-fixed.

- Add AppSettings.minimalDark (device-local, defaults dark) and a segmented
  Light/Dark picker under the Minimal toggle
- colorScheme now always returns a concrete value, so there is no clear
  operation left to fail; new private effectiveStyle is the single source of
  truth for both the SwiftUI and UIKit paths
- Trade-off: minimal no longer follows iOS automatically
- Changelog 2.30 dark-mode line rewritten
"
git push
```

## Step 4 — clean up locks

After the push, remove any git locks or stale locks (`.git/index.lock`, `.git/HEAD.lock`,
`.git/refs/**/*.lock`) so the next session starts clean. Confirm `git status` is clean and no
lock files remain before finishing.

## Report back

Whether the off→on repro is fixed, and how minimal light mode looks.
