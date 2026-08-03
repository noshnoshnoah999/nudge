# Handoff — Widget data + "All clear" fixes — 2026-07-24

This session found and fixed the REAL cause of the widget showing wrong reminders, plus a
related display bug. Two files changed. **Nothing built/committed yet** (Cowork has no Xcode).

## THE MAIN BUG (root cause found, fixed)

**Symptom:** the large Today widget showed reminders that were already **completed in the
app**, with **old dates** (24 Jun, 10 Jul) on 24 Jul.

**Root cause (confirmed in code + git):** commit `5de79fb` ("D1: per-item sync with
tombstones — kill whole-blob last-write-wins") moved the APP to per-item Supabase tables
(`reminders`, `lists`, `smart_lists`). The app **no longer writes the old `nudge_data`
blob** — only a comment in `Models.swift` still mentions it. But the WIDGET was still
reading `nudge_data` (`WidgetData.swift`). That table became a **frozen snapshot**, last
written around when the user enabled RLS and re-authenticated (the 6-digit email code).
So the widget showed stale, pre-RLS, already-completed reminders while the app was correct.

It was never the completed-filter, the token, or tinted mode. The widget was reading a
**dead table.**

**Fix:** rewrote `NudgeFeed.fetch()` in `ios/Nudge/NudgeWidgets/WidgetData.swift` to read
the per-item `reminders` and `lists` tables the app actually uses:
- Queries `reminders?select=id,data,deleted_at&deleted_at=is.null` and same for `lists`.
- Decodes per-item rows `{ id, data, deleted_at }`, skips tombstones, extracts `data` into
  the existing `WReminder` / `WList` shapes (field names verified to match the app's
  `Reminder` and `ReminderList` models exactly — plain camelCase, no CodingKeys override).
- Reminders are required (nil → widget shows "Can't sync"); lists are best-effort (a lists
  failure falls back to empty, colours default, rather than blanking the widget).
- Still uses anon key + the user's bearer token from the shared Keychain. No service-role
  key, no elevated access. The per-item tables have RLS live (per commit 5de79fb), so this
  moves the widget ONTO properly-protected tables.

## SECURITY ITEM TO CHECK (important — flag to Noah)

The old **`nudge_data` table may still exist in Supabase and may not have correct RLS.**
When the app moved to per-item tables it stopped using `nudge_data`, but the table (and its
frozen copy of the user's reminders) likely still sits in the database. Action for Noah /
Claude Code:
- In the Supabase dashboard, confirm whether `nudge_data` still exists.
- If it does: either confirm RLS policies scope it to the owning user, or **drop the table**
  so there's no stale, possibly-unprotected duplicate of user data. Nothing reads it anymore
  after this change.
- Do NOT do this blind — verify in the dashboard first. Don't paste keys anywhere.

## THE SECONDARY BUG (also fixed) — false "All clear" on failed fetch

Separately, a failed fetch used to return the same empty entry as "genuinely nothing due",
so both rendered "All clear". Fixed in `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`:
- Added `enum WLoadState { loaded, failed }` + `state` on `NudgeEntry`; `.failed` on nil fetch.
- TodayWidget shows a tappable "Can't sync — open Nudge" (`Link` to `nudgeapp://open`) instead
  of "All clear". "All clear" only shows on a successful, genuinely-empty fetch.
- OverdueWidget shows "— / can't sync"; ProgressWidget shows a sync glyph + "can't sync".

This is still correct and worth keeping, but note: the user's ACTUAL symptom was the dead-table
bug above, not a fetch failure. The per-item rewrite is the fix that makes their widget correct.

## NON-BUG explained: the grey circle top-right

The user's home screen is in **Apple "tinted" mode**. Tinted mode strips widget colours and
re-renders monochrome, so the coral "N overdue" pill shows as a grey blob with washed-out text.
This is the known Apple platform limitation (already in the original widget brief — "flag, don't
fix"). Switching to full-colour mode restores it. Optionally, the overdue pill could be made to
degrade more gracefully in tint (a glyph that reads in monochrome), but it can't be made
identical to colour mode. Not fixed this session; noted for later if Noah wants it.

## Files changed
- `ios/Nudge/NudgeWidgets/WidgetData.swift` — per-item table rewrite (the real fix)
- `ios/Nudge/NudgeWidgets/NudgeWidgets.swift` — failed-state handling (secondary fix)
- Deleted earlier this session: `ios/Nudge/Shared/WidgetBackgroundStore.swift` (App-Group draft,
  unusable on free team — see below)

## Free-team constraint (context, unchanged)
Confirmed via web search: App Groups need the paid ($99/yr) Apple Developer Program; the free
personal team can't create them. So "widget reads a snapshot the app writes" and the custom
background image / transparent widget are **shelved** until/unless Noah goes paid. The widget
reads Supabase directly (as it must on a free team).

## Verification needed in Claude Code (Cowork can't build)
Inspection-clean, NOT compile-verified. Claude Code must:
1. Build app + NudgeWidgets. (WidgetData rewrite: braces 28/28, parens 64/64; field names
   verified against `Reminder`/`ReminderList`.)
2. On-device: complete a reminder in the app, then check the widget updates on next refresh and
   the completed item disappears. Confirm old/done reminders are GONE from the widget.
3. Confirm the "Can't sync" state appears with an expired/absent session (not "All clear").
4. Check the `nudge_data` table in Supabase (security item above).
