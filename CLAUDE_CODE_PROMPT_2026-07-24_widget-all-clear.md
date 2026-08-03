# Claude Code prompt — Widget data fix (per-item tables) — 2026-07-24

Paste this into the Nudge Claude Code session.

---

## Context

Cowork found and fixed the real reason the widget showed **already-completed reminders with
old dates**. Two files changed. Full detail: `HANDOFF_2026-07-24_widget-false-all-clear.md`.

**Root cause:** commit `5de79fb` moved the app to per-item Supabase tables (`reminders`,
`lists`), and the app stopped writing the old `nudge_data` blob. But the **widget was still
reading `nudge_data`** — a now-frozen snapshot — so it showed stale, already-done reminders
that are correct in the app. Fixed by rewiring the widget to read the per-item tables.

**Files changed:**
- `ios/Nudge/NudgeWidgets/WidgetData.swift` — `NudgeFeed.fetch()` now reads per-item
  `reminders`/`lists` (`select=id,data,deleted_at&deleted_at=is.null`), skips tombstones,
  extracts `data` into `WReminder`/`WList`. (The real fix.)
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift` — failed fetch now shows "Can't sync — open
  Nudge" instead of a false "All clear" (secondary fix).
- Deleted: `ios/Nudge/Shared/WidgetBackgroundStore.swift` (do not re-add — App Group draft,
  unusable on the free Apple team).

## Do this, in order (confirm understanding first)

1. **Read** the handoff and the diffs on both changed files. Play back your understanding.

2. **Build** the Nudge app + NudgeWidgets extension. Fix any compile errors. (Field names in
   `WReminder`/`WList` were verified against the app's `Reminder`/`ReminderList`; the change
   is additive and self-contained.)

3. **Test the real fix on-device:**
   - Complete a reminder in the app. Wait for the widget's next refresh (or force it).
     → The completed reminder should DISAPPEAR from the widget.
   - Confirm the old/stale reminders (24 Jun / 10 Jul that were already done) are GONE.
   - Confirm the widget now matches what the app shows for today/overdue.

4. **Test the failed-fetch state:** with an expired/absent session, the widget shows
   "Can't sync — open Nudge" (not "All clear"). With a valid session and nothing due, it
   shows "All clear".

5. **SECURITY — check the orphaned `nudge_data` table (do NOT skip):**
   In the Supabase dashboard, check whether the old `nudge_data` table still exists. Nothing
   reads it after this change. If it exists, either confirm its RLS policies scope rows to the
   owning user, or drop the table so there's no stale, possibly-unprotected copy of user data.
   Verify in the dashboard first — do not act blind, and do not paste keys anywhere.

6. **Commit** with a clear message, e.g.
   `Widget: read live per-item reminders/lists tables (fix stale nudge_data blob); honest "Can't sync" state`.

7. **Push** to the remote.

8. **After committing and pushing, remove any git locks / stale locks**
   (`.git/index.lock`, `.git/refs/**/*.lock`, any leftover `*.lock`) so the next session
   starts clean.

## Rules
- Safety & security first. This change does not touch auth or keys. The `nudge_data` check in
  step 5 is a real security item — handle it carefully in the dashboard, don't guess.
- Do NOT build widget token-refresh (Step 2, staleness) this session — it's a separate,
  Noah-approved step. It's less urgent now that the widget reads live per-item data.
- If the on-device test still shows stale/done reminders after the rewrite, STOP and report —
  it would mean a second cause we haven't found.
