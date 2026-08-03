# Claude Code prompt — Minimal round 3, Apple grouped style (31 Jul 2026, session D)

Paste everything below the line into Claude Code in the Nudge repo.

---

Read `HANDOFF_2026-07-31d_minimal-apple-grouped.md` first. Build, fix compile errors, verify on
device, commit, push.

## Context

Third round on the Minimal design. Noah reported: the Minimal toggle looked broken, the Notion
icon still had an outline, the New Reminder sheet didn't match Apple Reminders — and then, mid
-session, "there are still outlines here" with screenshots of the Home stat tiles and Lists grid.

**The underlying mistake, now corrected:** round 2 worked to the rule "remove the container".
That's right for the reminder LIST and wrong everywhere else. Apple Reminders' *edit* screen is
full of grouped cards. The real rule is:

> Apple separates a card from the page with a **fill**, never a **stroke**, and the corners are
> **rounded (10pt), not square**.

Minimal previously had `Theme.surface` == `systemBackground` — the same colour as the page — so
every card fill was invisible and only its border showed. That is why outlined boxes kept
turning up one screenshot at a time.

## Step 1 — build

Build for iOS and macOS (Mac Catalyst). Fix compile errors.

New/changed API in `Theme.swift`:

- `Theme.cardStroke` — border colour for card shapes. `.clear` in minimal. **18 sites** across 9
  files were swept from `.stroke(Theme.hairline…)` / `.strokeBorder(Theme.hairline…)` to this,
  by script. `Theme.hairline` still exists and still means "divider between rows" — don't
  conflate them.
- `Theme.controlTint: Color?` — nil in minimal. **46 sites** swept from `.tint(Theme.accent)` /
  `.tint(Theme.violet)` / `.tint(settings.accent)`, by script. Note it's **optional**; if a call
  site needs a non-optional `Color`, use `Theme.accent` there instead of unwrapping.
- `Theme.accent` in minimal is now `Color(.systemBlue)` (was `Color(.label)`).
- `Theme.surface` → `secondarySystemBackground`, `surfaceAlt` → `tertiarySystemBackground`.
- `Theme.radius(N)` in minimal returns `min(N, 10)`, no longer 0.
- `AppSettings.controlTint` mirrors `Theme.controlTint`; `NudgeApp` uses it in `.tint(...)`.

Both sweeps were scripted, so scan the diff for a site where the mechanical replacement doesn't
type-check.

## Step 2 — verify on device

**Priority one: Minimal OFF must look completely unchanged.** The two sweeps touched ~64 call
sites on both code paths. Check at least Mocha and one other tinted theme against the current
committed build before you look at anything else.

Then, in minimal, hunt for any remaining hollow outlined rectangle. Noah has found these one
screen at a time for two rounds; find them all now. Walk: Home (stat tiles, Next up, banners),
Lists grid, Today, Overdue, Upcoming, Search, Settings (every section), New Reminder, Reschedule,
Bulk Move, Triage, Clean up, Changelog, Completed history, Group cards expanded.

Also check:

- Toggles are **green** with a visible knob (Settings and New Reminder). This was the "strange
  looking" toggle — white track under a white knob, because the accent was white.
- **Reminder rows must still be square and flat** with an inset divider. They pass 0 explicitly
  through `cardSurface`, so the new 10pt clamp should not reach them. If rows suddenly have
  rounded corners or a grey fill, that's the bug.
- **Light mode, not just dark.** `secondarySystemBackground` is a light grey on white. If the
  cards read as muddy or invisible in minimal light, say so rather than shipping it — the fix
  would be `systemGroupedBackground` for the page instead.
- New Reminder side by side with the Apple Reminders edit screenshot: grouped rounded cards,
  grey section captions, blue values, green switches.

## Step 3 — commit and push

Only after a clean build and checking minimal dark, minimal light, and a tinted theme.

```
git add -A
git commit -m "Minimal: Apple grouped-card style — fill not stroke, rounded not square

Third round. Outlined boxes kept reappearing because minimal set
Theme.surface to systemBackground (the same colour as the page), so card
fills were invisible and only their borders showed, and Theme.radius(0)
squared every container. Apple separates a card from the page with a fill,
never a stroke, with 10pt corners.

- Theme.surface/surfaceAlt -> secondary/tertiarySystemBackground in minimal
- New Theme.cardStroke (.clear in minimal); swept 18 rounded-rect borders
- Theme.radius clamps to 10 in minimal instead of flattening to 0; reminder
  rows stay square by passing 0 explicitly through cardSurface
- Theme.accent in minimal is systemBlue, not label: Reminders is a minimal
  app WITH an accent, and a white accent made Toggle a white track under a
  white knob
- New Theme/AppSettings.controlTint (nil in minimal) so switches are system
  green like Reminders; swept 46 tint sites
- Unbox the hand-rolled Notion header button, which never went through
  iconButton and so kept its outline
- Restore AddReminderView's sections and title field to filled rounded cards:
  the Reminders LIST is flat, but its EDIT sheet uses grouped cards
"
git push
```

## Step 4 — clean up locks

After the push, remove any git locks or stale locks (`.git/index.lock`, `.git/HEAD.lock`,
`.git/refs/**/*.lock`) so the next session starts clean. Confirm `git status` is clean and no
lock files remain before finishing.

## Report back

Whether it built, whether any outlined boxes survive (and where), how minimal **light** mode
looks, and whether the tinted themes are untouched.
