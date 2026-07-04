# Nudge — Group Reminders feature (handoff)

_Written: 2026-07-04 · native app (iOS + Mac Catalyst) only_

## What was built
A **non-destructive AI grouping** feature: Claude bundles related reminders into one
collapsible "group card" to clear clutter. Tap a group to expand and see all members; tap
again to collapse. Long-press a group (or use the review sheet) → **Ungroup**.

Two ways it runs:
1. **Manual** — Settings → *Group reminders* → "Group similar reminders now".
2. **Automatic at 23:50** — piggybacks on the existing carry-over background window. Auto-applies
   (safe because it's reversible), then shows an **orange banner** the next morning to review.
   A toggle ("Group automatically at 23:50") lets the user turn the nightly run off.

## Design decisions (and why)
- **Non-destructive, not a merge.** Grouping only sets three fields on each reminder
  (`groupId`, `groupTitle`, `groupSource`). Nothing is deleted, no due dates change. This is the
  only model that is safe to auto-apply overnight — Ungroup fully reverses it.
- **Conservative candidates.** `groupCandidates()` only considers reminders that are incomplete,
  not dismissed, not pinned, not protected (routines/recurring/escalating), not already grouped,
  and **either have no due date or are due >3 days out.** This guarantees nothing overdue or
  coming up soon is ever hidden inside a collapsed card.
- **Data model on the reminder, not a separate table.** `groupTitle` is denormalised onto each
  member so any client can render a group without a lookup table. The web PWA serialises whole
  reminder objects and preserves unknown fields, so `groupId` survives web round-trips.

## Files
New:
- `AIGrouper.swift` — Claude call (Sonnet) that clusters candidates into named groups (JSON
  schema output). Sanitises: ≥2 members/group, each id used once. Mirrors `AICarryOver`.
- `GroupLog.swift` — persistent run log + orange-banner state (UserDefaults, ~31 days). Mirrors
  `CarryOverLog`.
- `GroupCardView.swift` — the collapsible group card + the `ListItem` enum (`.single`/`.group`).
- `GroupViews.swift` — `GroupReviewView` (morning review sheet) + `GroupHistoryView` (Settings).

Edited:
- `Models.swift` — added `groupId` / `groupTitle` / `groupSource` + `isGrouped` to `Reminder`.
- `NudgeStore.swift` — `groupCandidates`, `applyProposedGroups`, `ungroup`, `groupNowAI`
  (manual), `maybeRunDailyGrouping` (23:50), `listItems` (collapses a flat list into rows).
- `ContentView.swift` — orange `groupBanner`, `showGroupReview` sheet, `maybeRunDailyGrouping`
  in the `.task` and foreground `scenePhase`, and `groupedRows()` used in Today / Overdue tabs and
  the Upcoming `sectionView`.
- `SyncSettingsView.swift` — "Group reminders" section: button + nightly toggle
  (`@AppStorage("autoGroupNightly")`, default on) + history link.
- `BackgroundTasks.swift` — calls `maybeRunDailyGrouping()` in the overnight BG task.
- `Changelog.swift` — v2.28 entry.

## Where groups actually appear
Grouped reminders are, by design, no-date or far-off — so they surface on the **Upcoming** tab
(the "No date" and "Upcoming" sections). Today/Overdue tabs call `groupedRows()` too, but they'll
show only singles since near-term items are never grouped. This is intentional.

## Known follow-ups (NOT done this session)
- **Per-list view (`FilteredListView`) left flat.** It uses drag-and-drop for sections; injecting
  group cards there needs care so it doesn't fight `.draggable`. A grouped reminder still shows as
  a normal card inside its list — non-breaking, just not collapsed there.
- **Web PWA = "respect only" (Option B), not yet built.** Next session: make `index.html` render
  and expand `groupId` groups + a manual Ungroup. No AI on web (would leak the API key). Confirm
  the web doesn't strip `groupId` on write (it appears not to — it serialises whole reminders).
- **Cannot compile in Cowork** (no Xcode in the sandbox). Needs a build pass on the Mac; fix any
  Swift errors there. See `CLAUDE_CODE_PROMPT.md`.

## Safety notes
- API key is read from `UserDefaults "anthropic_api_key"` on-device only (same as carry-over /
  smart reschedule). No key ever enters this repo or any prompt.
- AI can only reorganise the visible pile — it cannot create, move, complete, or delete reminders.
