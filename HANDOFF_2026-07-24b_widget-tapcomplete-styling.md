# Handoff — Today widget: tap-to-complete + edit-mode styling — 2026-07-24 (session b)

Two new features written in Cowork. **Not built/committed** (no Xcode in Cowork). Follows the
earlier same-day fix (per-item table rewrite + false-"All clear"), which is already on-device
and working per Noah.

## Feature 1 — Tap-to-complete on the Today widget

Tapping a reminder row in the large Today widget marks it done **without opening the app**.

**Key constraint discovered:** `NudgeStore` is in the APP target only (`Nudge/NudgeStore.swift`),
NOT in `Shared/`. A widget `Button(intent:)` runs in the WIDGET process, so it cannot call
`toggleComplete`. Therefore the completion is written **directly to Supabase** from the intent.

**New file:** `ios/Nudge/Shared/CompleteReminderWidgetIntent.swift` (compiled into both targets)
- `CompleteReminderWidgetIntent` (AppIntent, `@Parameter reminderId`).
- `WidgetCompletion.complete(id:)`: fetches the reminder's FULL `data` JSON from the per-item
  `reminders` table, flips `completed=true`, `completedAt=<iso now>`, `snoozedUntil=null`,
  `updatedAt=<stamp now>`, then upserts the whole row back (`on_conflict=user_id,id`,
  `Prefer: resolution=merge-duplicates,return=minimal`) with a fresh `updated_at`.
- Writes back the FULL data (not a subset) so notes/recurrence/etc. aren't wiped, and stamps a
  fresh `updated_at` so the app's last-write-wins sync doesn't clobber the completion.
- `JSONVal` enum: round-trips arbitrary reminder JSON without a full Codable model in the widget.
- `WidgetReload.today()`: reloads the "NudgeToday" timeline so the item drops off immediately.
- Anon key + Keychain bearer token; RLS on `reminders` scopes the write. No service-role key.

**Wiring:** in `NudgeWidgets/NudgeWidgets.swift`, each Today row is now wrapped in
`Button(intent: CompleteReminderWidgetIntent(reminderId: it.id))` with `.buttonStyle(.plain)`.
The colour dot became a ring to read as "tap to tick".

**KNOWN LIMITATION (by design, Noah agreed):** a RECURRING reminder completed from the widget
does NOT spawn its next occurrence here — that happens when the app next opens and runs
`toggleComplete`'s logic. One-off reminders complete perfectly. Acceptable for the common case.

## Feature 2 — Edit-mode styling for the Today widget

Long-press the Today widget → Edit Widget → choose Font / Text size / Spacing / Grayscale.
On a free Apple team there's no App Group, so styling is stored per-widget via an AppIntent
configuration (no shared container needed).

**New file:** `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
- `WidgetFont` (Default/Rounded/Serif/Monospace → `Font.Design`), `WidgetSpacing`
  (Compact/Comfortable/Airy) — `AppEnum`s.
- **Font size is NUMERIC** (not an enum): `TodayWidgetConfigIntent` has
  `@Parameter(title:"Font size", default:22, controlStyle:.stepper, inclusiveRange:(12,40)) var fontSize: Int`.
  (Swap `.stepper` → `.slider` for a drag slider — both valid.) `widgetFontSizeRange`/`Default`
  constants live here.
- `TodayWidgetConfigIntent: WidgetConfigurationIntent` with Font / fontSize / Spacing / Grayscale.
- `TodayStyle`: resolved values (design, titleSize, rowSpacing, grayscale); clamps fontSize to range.

**Dumb-Phone look (updated per Noah's screenshots):** the Today list is restyled to match the
"Dumb Phone" launcher app. Each row is JUST the reminder title — forced `.lowercased()`, `.bold`,
left-aligned, at the chosen point size. NO coloured ring, NO due-date label. Long titles cut off
cleanly at the trailing edge with NO ellipsis (`lineLimit(1)` + `fixedSize` + `clipped`, not tail
truncation). `maxRows` now scales with font size + spacing so big text doesn't overflow the widget.

**Wiring in `NudgeWidgets.swift`:**
- `TodayWidget` switched from `StaticConfiguration` → `AppIntentConfiguration` with a new
  `TodayConfigProvider: AppIntentTimelineProvider` and `TodayConfigEntry` (base entry + style).
- The other four widgets (Overdue/Progress/QuickAdd/QuickAddLock) are UNCHANGED.
- `TodayWidgetView` gained `var style: TodayStyle = .default`; applies `style.rowSpacing`,
  `style.titleSize` + `style.design` on the lowercase bold title, size-aware `maxRows`, and
  `.grayscale(...)` on the whole view.

**KNOWN ONE-TIME COST (tell Noah):** changing Today from StaticConfiguration to
AppIntentConfiguration will reset any already-placed Today widgets once. He re-adds the widget and
re-picks options a single time. Not data loss.

**Grayscale + tinted mode:** Noah's home screen is in Apple "tinted" mode, which already strips
colour. So the grayscale toggle only visibly changes things in full-colour mode. Not a bug.

## Verify in Claude Code (Cowork can't build)
Inspection-clean, NOT compile-verified. Braces/parens balanced (interpolation-aware check passed).

1. Build app + NudgeWidgets. Likely nitpick to watch: `AppEnum.caseDisplayRepresentations` —
   if the SDK wants it as a computed `static var` rather than a stored one, adjust. Trivial.
2. Test tap-complete on-device: tap a Today reminder → it completes without opening the app,
   drops off the widget, and shows completed in the app + other devices after sync. Test a
   one-off (should be perfect) and a recurring one (completes, but confirm next occurrence
   appears after opening the app).
3. Test Edit mode: long-press Today → Edit → change Font/Size/Spacing/Grayscale → confirm each
   visibly changes the widget. (Grayscale only visible in full-colour home-screen mode.)
4. Expect to re-place the Today widget once due to the config-type change.
5. Commit + push + clear stale locks.

## Files
- New: `ios/Nudge/Shared/CompleteReminderWidgetIntent.swift`
- New: `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`
- Changed: `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`
- Prompt: `CLAUDE_CODE_PROMPT_2026-07-24b_widget-tapcomplete-styling.md`
