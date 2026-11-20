# Handoff — 2026-11-20: Breakfast list + buy reminders — COMPLETE

All parts built, installed (iPhone + Mac), pushed, and confirmed working by Noah on 2026-11-20.
`origin/main` = `c402d50` at the end of this session (plus this docs commit).

Earlier context: `handoffs/HANDOFF_2026-11-19_breakfast-nudge-sync.md` (spec + Budget↔Nudge
contract, section 12) and `HANDOFF_2026-11-19b_breakfast-list.md` (first Nudge build).

## 1. Breakfast list (shared with Budget)
- `BreakfastSync.swift` — `BreakfastStore`: reads `breakfast_list` in **Budget's** Supabase
  project (publishable key in the gitignored `Shared/Secrets.swift`, `apikey` header only;
  Nudge's own session token never sent). PATCHes only status/done_on/changed_by/updated_at,
  guarded by `status=neq.skipped&updated_at=lt.<stamp>`; offline queue. Never touches finance_data.
- `BreakfastView.swift` — Home card (under Next up / Still due, above Pinned) → sheet:
  unbought on top by shop; collapsed **Bought** list per week (newest day first, bought day shown);
  next week same; **two taps** to tick/untick with a heartbeat on the first tap (3 s window).
  Skip → message + Open Budget (`budget://breakfast?week=`).

## 2. Buy reminders (Noah's final rules)
- Planner (bell "Remind me" or long-press an item): "Everything unbought" (snapshot when set;
  weekly re-snapshots each week) or picked items with counts; date/time; once (this/next week) or
  weekly. **Review** summary before saving; exact duplicate for the same week **blocked**,
  overlap **warns**.
- Normal reminder in the **Breakfast** list with `Reminder.breakfast` (`BreakfastPlan`).
  Titles never name the shop: "Buy: Single Lemon ×2", "Breakfast: 6 things to buy".
- **Never completed by hand.** Guard at the top of `NudgeStore.toggleComplete` (all paths) routes
  to `AppRouter.pendingBreakfast`; it completes itself only when everything it covers is ticked or
  skipped (`syncBreakfastReminders`, `breakfastAutoCompleting`). Partly bought → title drops.
- Opening from a reminder (card tap, notification "Open list"/tap, widget, banner) shows its items
  grouped on top: "REMINDER FOR <day date, time>".
- Cards: cart icon, "Tap to open the list · Hold to reschedule or delete"; long-press has no
  Complete/Edit. Sorted first on Today / Overdue / Upcoming (Home unchanged).
- Notification category `NUDGE_BREAKFAST`: Open list / Snooze 1 hour / Reschedule… (no complete).
- Past midnight and not done → banner on Home top + shopping list: Reschedule / Delete
  (weekly: delete this week / stop weekly). AI carry-over / smart reschedule / bulk move skip them.
- Widget: Breakfast reminders first; row is a `Link` to `nudgeapp://breakfast?r=<id>` (id validated
  in `NudgeApp.onOpenURL`); `CompleteReminderWidgetIntent` refuses Breakfast rows.

## Commits (in order)
67a415e list · 286c62e card position · 773af92 layout + two-tap · d437857 reminders step 1 ·
68bdd9a reminders v2 · 25c512b widget (+ docs commits; prompts `CLAUDE_CODE_PROMPT_2026-11-19b…`
to `…2026-11-20d…`).

## Known limits
- A Nudge tick reaches Budget only when Budget is opened (no server push).
- `breakfast_list` is open to anyone with Budget's publishable key (Noah's accepted choice).
- The widget lists today's items; a missed (past-day) Breakfast reminder only appears there when
  today is empty — it is always on the Overdue tab and the Home banner.
- A delivered notification keeps its old text; pending ones update with the title.
- Budget↔Nudge contract: don't change breakfast_list columns, status values or row id format
  without telling both Claudes (spec section 12).
