# Handoff — 2026-08-06: Today widget stops showing past-day overdue

**Status:** written in Cowork, NOT built, NOT committed, NOT tested on device.
**Files changed:** `ios/Nudge/NudgeWidgets/NudgeWidgets.swift` (only file).

---

## The bug Noah reported

The Today widget was listing overdue reminders from yesterday and earlier. His rule:
an item due *today* whose time has passed is fine to show (it's still today until midnight),
but once it rolls past midnight uncompleted it should drop off the Today widget.

## Why he was right

This is not a new rule — the app has drawn exactly this line since the Today/Overdue tab
split. `NudgeStore.pastDayOverdue()` (NudgeStore.swift:1485) is documented as:

> Reminders for the Overdue page: due on a PREVIOUS calendar day. A reminder due earlier
> *today* (time already passed) stays on the Today page — it only lands here once midnight
> rolls it into a past day.

`ContentView.overdueTab` uses that. The widget did not. `NudgeProvider.build()` tested
`d < now`, which is true for anything past its time ever, so the widget's Today list was
"today + the entire historical overdue pile". Same class of divergence as the
RecurrenceEngine bug fixed on Aug 5: widget logic drifting from app logic.

## A second bug found in the same expression

`isOver = d < now` ignored `hasTime`. The app's `NudgeStore.isOverdue()` (line 1412)
deliberately treats a date-only reminder as not overdue until its whole day has passed,
"otherwise it reads as overdue from 00:01 on the very day it's due". The widget had no such
cutoff, so a no-time reminder due today rendered red from midnight. Fixed in the same change.

---

## What changed

### 1. `build()` splits the two piles instead of merging them

`todayItems` (due today) and `pastDayItems` (`startOfDay(due) < startOfDay(now)`) are now
collected separately and never mixed.

### 2. `isOver` gained the day-end cutoff

```swift
let cutoff = hasTime ? d : (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: d)) ?? d)
let isOver = cutoff < now
```

Mirrors `NudgeStore.isOverdue()`.

### 3. Fallback rule (Noah's explicit choice)

- Today has **anything** open → show **only** today's items. Past-day pile hidden entirely.
  It does **not** fill leftover rows — Noah chose the strict version.
- Today **completely empty** + past-day exists → show a `"N overdue"` caption, then the
  past-day items.
- Both empty → `"All clear"` (unchanged).

`NudgeEntry` gained `var showingOverdue: Bool = false` to carry which state the list is in.
Defaulted, so the sample/empty/failed/signedOut initialisers still compile.

### 4. Small Overdue widget count is now past-day only

`entry.overdue` = `pastDayItems.count`, matching `pastDayOverdueCount()` and the Overdue tab.
Previously it counted anything past its time including earlier today, so the widget and the
app's Overdue tab could show different numbers.

### 5. Past-day pile sorts high-priority first

Matches the app's Overdue tab ordering (`prank` then date). `WItem` gained
`var priority: String = "normal"` for this. **Today's list is unchanged — still purely
chronological.** Flagged to Noah as a judgment call; revert this bit if he'd rather the
fallback list stay in pure time order.

### 6. Midnight refresh — `wNextRefresh()`

Today-vs-past-day is now a calendar-day test, so every item flips category at 00:00. On the
old flat 30-minute cadence the widget could sit half an hour past midnight still presenting
yesterday's reminders as today's — the exact confusion this change removes. Both timeline
providers now request `.after(min(now+30min, nextMidnight))`. WidgetKit treats `.after` as
"no earlier than", so this is a floor, not a guarantee.

### 7. Caption height is pinned

`rowLimit(for:)` now receives `geo.size.height` minus the caption height when the caption is
showing. The caption is `.frame(height: 13)` with `.lineLimit(1)` + `.minimumScaleFactor(0.7)`
so Dynamic Type shrinks it rather than growing the row and overflowing the widget — the
overflow bug the GeometryReader rewrite already had to fix once.

---

## What to verify on device

1. **Main case** — with overdue items from yesterday or earlier AND items due today, the
   Today widget shows only today's.
2. **Date-only today** — a reminder due today with no time is NOT red before its day ends.
3. **Fallback** — complete everything due today; widget should flip to `"N overdue"` + the
   old items, not `"All clear"`.
4. **Truly empty** — no today items, no past-day items → `"All clear"`.
5. **Small Overdue widget** — its number equals the app's Overdue tab count exactly.
6. **No overflow** — in the fallback state at the largest configured font, rows stay inside
   the widget (this is the state with the extra caption line).
7. **Tap-to-complete still works** in the fallback state (ids are unchanged, so it should).

## Known repo state at handoff

- Stale `.git/index.lock` present — Cowork can't remove it (Operation not permitted).
  Claude Code should clear it.
- Two untracked files from the Aug 5 session are still uncommitted:
  `HANDOFF_2026-08-05_widget-recurring-completion.md` and
  `CLAUDE_CODE_PROMPT_2026-08-05_widget-recurring-completion.md`. Decide whether to commit
  them alongside.
- Last commit: `f2c8e39` "Widget: complete recurring reminders the way the app does".
