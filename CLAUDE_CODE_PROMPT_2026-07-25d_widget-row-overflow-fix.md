# Claude Code prompt — Today widget row overflow fix (2026-07-25d)

Small follow-up to `2026-07-25c`. **The background fix worked** — the widget now renders true
black and blends into the wallpaper in Apple tinted mode. This fixes a layout regression that
the same change introduced.

## The bug

After 25c, the widget showed only the **last** reminder(s) in the list, with the rest missing.
Increasing the font size in Edit mode revealed the real symptom: the top row was drawn
**above the widget's top edge**, clipped off. The list was rendering with items 1–5 outside the
visible area; only the tail was inside. It looked like "only one reminder is showing".

Two independent faults, both introduced/exposed by 25c:

1. **Vertical offset (regression from 25c).** The background was placed in a
   `ZStack { background.ignoresSafeArea(); content }`. `ignoresSafeArea()` expands that child
   past the widget bounds, enlarging the ZStack's layout region; the ZStack's default `.center`
   alignment then positioned the content against that enlarged region, pushing it upward. The
   bottom overflow was the list's invisible trailing `Spacer`, which is why it read as empty
   space rather than as a shifted layout.

2. **`maxRows` over-counted (pre-existing, made visible by 1).** It computed a row as
   `titleSize + rowSpacing`, but a row is actually `titleSize * 1.15` tall — see
   `WidgetRowTitle`'s `.frame(height: size * 1.15)` — plus the spacing. It also hardcoded the
   usable height (320pt large / 130pt medium), which `.contentMarginsDisabled()` had changed.
   Both errors pushed the same direction, so it always thought more rows fit than did.

## The fix

`ios/Nudge/NudgeWidgets/NudgeWidgets.swift`:

- `TodayWidget` no longer uses a `ZStack`. The background is applied with **`.background { }`**
  on the content, after an explicit
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`.
  `.background { }` draws behind the content, sized to the content's frame, and takes no part
  in layout — so it cannot shift anything. `.ignoresSafeArea()` removed.
- `maxRows` replaced by `rowLimit(for: CGFloat)`, driven by a `GeometryReader` around the
  list so the count comes from **real available height** rather than hardcoded constants. Row
  height now correctly `titleSize * 1.15 + rowSpacing`, with `+ rowSpacing` in the numerator
  because N rows have N−1 gaps.
- `.clipped()` added to the list as belt-and-braces so nothing can ever paint outside the
  widget again, whatever the font size.

`ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift`: doc comment corrected (it still described the
ZStack approach).

## What to do

1. `git diff` and review.
2. Build the widget extension and app.
3. Install and check on device, in Apple **tinted** mode with a **near-black** background preset:
   - **All of today's reminders show**, starting from the FIRST one, top-aligned. Cross-check
     the list against the app's Today tab — Noah confirmed the reminders were never completed,
     so the widget list should match.
   - **No row is clipped at the top edge.**
   - Step the font size up and down in Edit mode across its range (12–40). At every size the
     rows must stay inside the widget: fewer rows at large sizes, more at small, never
     overflowing and never leaving a huge empty gap with rows missing.
   - Try both Compact and Airy spacing.
   - Check `systemMedium` as well as `systemLarge`.
   - **Confirm the background is still true black** — do not regress 25c. Sample the pixels:
     card interior and wallpaper should both be `#000000`.
4. Commit, e.g.
   `fix(widget): pin Today list to top and size rows from real geometry`
5. Push to `origin/main`.
6. **After committing and pushing, remove any locks or stale locks** (`.git/index.lock`,
   leftover Xcode DerivedData locks) so the next session starts clean.

## Safety notes

- Widget layout only. No data model, auth, or sync changes.
- No secrets; don't add any.
- Do not reintroduce `ZStack` for the background — that's the exact cause of this bug.

## Also worth raising with Noah (not a code change yet)

Widget rows are **tap-to-complete** (`a0c7da5`) — a single tap writes a completion straight to
Supabase with no confirmation. During this session's repeated visual testing that was briefly
suspected of having silently completed seven reminders. It hadn't, but the fact it was a
credible theory is itself a signal. Worth asking whether tap-to-complete should require a
confirmation, or move to a dedicated hit area rather than the whole row.
