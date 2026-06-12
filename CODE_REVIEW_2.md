# Nudge — Code Review #2 — ✅ ALL FIXED 2026-06-12

Second-pass scan, 2026-06-12. Focus: bugs in the **nightly-routine check-in** feature
(`routine`/`escalation` on `Reminder`) and its conflicts with the older sync / web / triage
systems. Work through P0 → P2 in order. Each item says exactly what's wrong, where, and what
to change. Previous review (`CODE_REVIEW.md`) is fully fixed — don't redo it.

**Background you need:** "Routine" reminders (currently *KP Body Scrub Night*, *Epiduo Night*)
never complete; ticking one means "did it tonight" and advances `dueDate` in place by
`NudgeStore.routineIntervalDays()` (escalation phases override recurrence). If one isn't
ticked by the next morning, the first app-open shows `RoutineCheckInView` ("did you do it
last night?"). `completedAt` is deliberately set on these still-open reminders so the
"Done today" stats count the tick — do NOT "fix" that.

---

## P0 — Routine feature broken in real flows

### 1. ✅ Morning check-in never appears when Face ID app-lock is on
`ContentView.maybeRoutineCheckin()` guards `!isLocked` and is called only from the launch
`.task` and `scenePhase == .active` — both fire while the app is still locked, and
`attemptUnlock()` (ContentView, ~line 727) never re-calls it after a successful unlock.
With app-lock enabled the sheet is simply never shown. (The day-key is correctly NOT burned
when locked, so the retry will work.)
**Fix:** in `attemptUnlock()`, after `LockShield.shared.hide()`, call `maybeRoutineCheckin()`.

### 2. ✅ Ticking a routine before its due time doesn't advance it
`NudgeStore.routineDidIt(_:night:)` uses `while next <= Date()` — a `while` loop. If the user
ticks KP at 20:30 and it's due 21:00, `next` (21:00) is already in the future, the loop never
runs, and the reminder stays due **tonight**: the 21:00 notification still fires and the next
morning's check-in asks about a night they already confirmed.
**Fix:** make it advance at least once — `repeat { next = cal.date(byAdding: .day, value:
interval, to: next)! } while next <= Date()` (do-while). All existing call paths stay correct
(verify: lapsed-yesterday → advances past now; ticked-after-due-time → same result as today).

### 3. ✅ Same bug's sibling: `toggleComplete` anchors on the wrong night
`NudgeStore.toggleComplete` routine path calls `routineDidIt(r.id, night: Date())`. For a
routine that lapsed (due yesterday) and is ticked from the list today, this anchors the next
occurrence on *today's* evening instead of the scheduled night — inconsistent with the
check-in sheet, which passes the due date.
**Fix:** pass `night: parseDate(reminders[i].dueDate) ?? Date()`. Combined with item 2's
do-while, both paths then produce identical scheduling.

### 4. ✅ Completing a routine in Apple Reminders or on the web kills the cycle
Two entry points bypass `routineDidIt`:
- **Apple:** `RemindersSync.reconcile` (Apple-newer branch, ~line 344) applies
  `writeToNudge`, which sets `completed = true` on the routine. A completed routine is
  excluded from `lapsedRoutinesForCheckin()` and never advances — the routine silently dies.
- **Web:** `index.html` `completeReminder()` (~line 1076) marks it completed AND spawns a
  next-occurrence copy from `recurrence` — dead routine **plus** a duplicate.

**Fix (iOS):** extract the advance math from `routineDidIt` into a helper, e.g.
`NudgeStore.advanceRoutine(_ r: inout Reminder, night: Date)` (sets dueDate forward,
`completed = false`, `completedAt = iso(Date())`, clears snooze). In `reconcile`'s
Apple-newer branch: after `writeToNudge(&rr, from: ek)`, if `rr.routine == true &&
rr.completed == true`, call the helper with `night: parseDate(cur.dueDate) ?? Date()` —
the next sync pass will write the uncompleted/advanced state back to Apple.
**Fix (web):** in `completeReminder`, if `r.routine`: do NOT spawn a copy and do NOT set
`completed = true`; instead advance `r.dueDate` in place (+interval days from its due
date, do-while past now, keep the time-of-day; interval = active `r.escalation` phase's
`everyDays`, else recurrence daily interval, default 1) and set `r.completedAt`.

---

## P1 — Conflicts with older systems

### 5. ✅ Smart Reschedule / Triage will fling lapsed routines into next week
`NudgeStore.smartReschedule` plans **all** `isOverdue` reminders — a lapsed KP/Epiduo gets
redistributed to a random slot with `hasTime` rewritten, fighting the morning check-in.
`stuckReminders()` can likewise flag routines for triage.
**Fix:** exclude `r.routine == true` in both `smartReschedule`'s overdue filter
(NudgeStore ~line 513) and `stuckReminders()` (~line 533).

### 6. ✅ Snoozing a routine permanently shifts its "evening" anchor
`NudgeStore.snooze` (~line 408) rewrites `dueDate = now + minutes`. Routine scheduling derives
its evening hour from `dueDate` (`routineEveningComponents`), so snoozing KP at 23:40 makes
every future occurrence 00:40.
**Fix:** in `snooze`, if `routine == true` set only `snoozedUntil` (+ `updatedAt`), leaving
`dueDate` untouched. Notifications already fire at `max(due-based, snoozedUntil)` so the
re-alert still works.

### 7. ✅ Card shows the wrong frequency after a step-up
`ReminderCardView` shows `recurText(r.recurrence)` ("every 3 days") but escalation phases
override the real cadence (`routineIntervalDays`), so after a "step up" the card lies.
**Fix:** in the repeat badge, when `r.routine == true && !(r.escalation ?? []).isEmpty`,
display `"every \(store.routineIntervalDays(r))d"` instead of `recurText`.

### 8. ✅ Likely crash: escalation phase editor iterates indices while deleting
`AddReminderView.routineEditor` uses `ForEach(escalation.indices, id: \.self)` with bindings
(`$escalation[i]`) and an inline remove button — the classic SwiftUI stale-index crash when
deleting a row.
**Fix:** make `EscalationStep` Identifiable (`var id: String = UUID().uuidString`, with a
custom `init(from:)` defaulting missing ids so existing cloud JSON still decodes; web
preserves unknown keys), iterate `ForEach($escalation)`, remove by id.

---

## P2 — Polish / consistency

### 9. ✅ Small drift + gaps
- `SyncSettingsView` Safety footer still says "last 40 kept" — rotation is now 60.
- Pinned Upcoming sections (`ContentView.upcomingTab`) include items due **today** and
  snoozed items, duplicating the Today tab. Consider filtering to `d > today-end` (or at
  least excluding snoozed) — confirm preferred behaviour with Noah if unsure, default to
  excluding today's items.
- Feature gap (note, don't build unless trivial): KP was requested as "3×/week on fixed
  days"; the model only supports every-N-days. A weekday-set schedule
  (e.g. Mon/Wed/Fri) would need a `weekdays: [Int]` option on the routine.

---

## Verify after fixing
1. Compile: `xcodebuild -project ios/Nudge/Nudge.xcodeproj -scheme Nudge -destination
   'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates CODE_SIGN_IDENTITY="-"
   CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
2. Logic checks (no test target exists; reason through or add pure-Swift asserts):
   tick-before-due advances exactly one interval; lapsed+ticked-from-list matches
   check-in behaviour; Apple-completed routine comes back uncompleted & advanced after
   one sync; web complete on routine spawns nothing.
3. Deploy BOTH devices: `./reinstall_nudge.sh` (iPhone must be unlocked, screen on; if
   preflight fails, relaunch the Mac app from DerivedData and retry the script later).
4. The Supabase blob is live personal data — no destructive experiments. Update this file
   marking each item ✅/⏭ and summarise what changed.
