# Claude Code prompt — Today widget background colour + tinted-mode fix (2026-07-25)

Cowork made source edits for a Today-widget background colour picker AND a fix
for Apple tinted-mode background stripping, but cannot build, test, commit, or
push in this repo. Please pick up from here.

## Context

Read `HANDOFF_2026-07-25_widget-background-color.md` first — it has the full
rationale, the verified root cause, and a documented fallback plan.

Short version:
1. Added a "Background" option to the Today widget's Edit-mode config:
   System Default / Soft Black `#0B0B0B` / True Black `#000000`. Hex values were
   sampled from Noah's actual device, not approximated.
2. In Apple's **tinted** Home Screen mode the picker did nothing, because tinted
   mode renders in `.accented` and WidgetKit **discards `containerBackground`** and
   substitutes its own grey material. Fixed with the documented opt-out
   `.containerBackgroundRemovable(false)` on `TodayWidget`.

Files already edited (uncommitted):
- `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`

## What to do

1. Run `git diff` to review the actual edits before doing anything else.
2. Build the `NudgeWidgets` extension target and the main app target; fix any
   compile errors. Watch specifically for:
   - `AnyShapeStyle` in `NudgeWidgets.swift`'s `TodayWidget.body` — confirm it compiles against the `.containerBackground` overload used elsewhere in the file.
   - `Color(wHex:)` — confirm the initializer exists in `WidgetData.swift` (other `WTheme` colours use it) and is visible from `TodayWidgetStyle.swift` (same target).
   - `.containerBackgroundRemovable(false)` — confirm it's valid on `AppIntentConfiguration` at the project's iOS 26.5 deployment target.

3. **On-device testing is the important part here — this cannot be validated by a clean build alone.**
   On a real device (or simulator with Home Screen customization available):
   - Long-press Today widget → Edit Widget → confirm a new "Background" row appears with System Default / Soft Black / True Black.
   - In **normal / full-colour** Home Screen mode: picking Soft Black and True Black visibly changes the widget background.
   - In **Apple tinted** Home Screen mode, with a **near-black tint colour selected** (this is Noah's actual setup): confirm the widget now renders near-black and blends into the wallpaper, instead of the old grey card.
   - **CRITICAL CHECK — reminder titles must still be legible in tinted mode.** Forum thread 768862 reports `containerBackgroundRemovable(false)` can pull content into the tint treatment even when non-accentable. With a near-black tint, titles could go black-on-black and disappear. Verify the titles are still readable.

4. **If titles vanish or become unreadable in tinted mode**, apply the fallback documented in the handoff:
   - Remove `.containerBackgroundRemovable(false)`.
   - Add `.contentMarginsDisabled()` to `TodayWidget`.
   - Wrap `TodayWidgetView` in a `ZStack` with `style.backgroundColor` as the bottom layer filling the full bounds; use `.containerBackground(.clear, for: .widget)`.
   - Manually restore the padding that content margins were providing.
   Then re-test steps in (3). Note in the commit message that the fallback path was used.

5. Also sanity-check that the other widgets are visually unchanged: Overdue,
   Progress, QuickAdd, and the Lock Screen quick-add. Scope is Today widget only.

6. Commit with a clear message, e.g.:
   `feat(widget): Today widget background colour picker + keep background in tinted mode`

7. Push to `origin/main`.

8. **After committing and pushing, remove any locks or stale locks** (e.g.
   `.git/index.lock`, leftover Xcode DerivedData lock files) so the next session
   starts clean.

## Safety notes

- No secrets or API keys involved. Do not add any.
- Widget UI/config code only — no data model, auth, or sync logic touched.
- Don't modify `Overdue`, `Progress`, `QuickAdd`, or the Lock Screen widget.

## Report back

Tell Noah specifically: (a) whether the primary fix worked or the fallback was
needed, and (b) whether titles stayed legible in tinted mode with a black tint.
Those are the two open questions from this session.
