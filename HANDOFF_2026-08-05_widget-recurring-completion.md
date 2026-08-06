# Handoff — 2026-08-05: Widget completion kills recurring reminders

## The bug Noah reported

On the night of **4 Aug 2026** Noah completed **Epiduo Night** and **KP Body Scrub Night** from
the Today widget. Both are repeating (nightly routine) reminders, so he expected them to roll
over to their next due date. Instead the widget marked them permanently complete, exactly as if
they had been one-off tasks. The series stopped dead.

He has already recovered both by hand (untick from the Completed list), so no data is lost.
This change stops it happening again.

## Root cause

Two completion paths existed and only one knew the rules.

**App** — `NudgeStore.toggleComplete` (NudgeStore.swift:~514):

- `routine == true` → `routineDidIt`: writes a completed *history snapshot* of tonight's
  occurrence, then `advanceRoutine` rolls the original forward, still open.
- plain `recurrence` → completes this one and inserts the next occurrence as a new row.

**Widget** — `WidgetCompletion.complete` (Shared/CompleteReminderWidgetIntent.swift): set
`completed = true`. Full stop. It never looked at `routine` or `recurrence`. It cannot call
`toggleComplete`, because `NudgeStore` is compiled into the app target only and a widget
`Button(intent:)` runs in the extension's process.

**The part that made it silent.** That file's own header claimed routines and recurrences were
"reconciled the next time the app opens and runs its own logic." No such reconcile existed for
this path. The only roll-forward-on-merge repair in the codebase is `RemindersSync.swift:389-399`,
and it fires exclusively for items ticked in **Apple Reminders** — not for Supabase writes.
`CloudSync.swift` has no recurrence logic at all. So the widget path had no safety net whatsoever,
and a comment asserted that it did.

## The fix

New file **`ios/Nudge/Shared/RecurrenceEngine.swift`** — the single source of truth for
"when does this repeating thing happen next", compiled by **both** targets:

- `completionKind(isRoutine:rule:)` → `.routine` / `.repeating` / `.oneOff`
- `nextOccurrence(afterDue:rule:now:)`
- `routineIntervalDays(escalation:rule:now:)` (escalation phases honoured)
- `eveningComponents(ofDue:)`
- `advancedRoutineDue(night:currentDue:escalation:rule:now:)`

Pure Foundation, `nonisolated` (the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
It cannot reference `Recurrence` / `EscalationStep` / `Reminder`, because `Nudge/` is an app-only
synchronized group the widget target does not compile. So it defines two tiny value types,
`Rule` and `EscalationPhase`, and each side maps onto them.

**`NudgeStore` now delegates** — `nextOccurrence`, `routineIntervalDays`,
`routineEveningComponents` and `advanceRoutine` are thin wrappers over the engine. Behaviour is
unchanged (verified, see below). `Models.swift` gained `Recurrence.engineRule` and
`Reminder.enginePhases` as the bridge.

**The widget now branches like the app.** `WidgetCompletion.complete` classifies the item and:

| Kind | What the widget writes |
|---|---|
| Routine | History snapshot row (completed, dated the night it was due, `recurrence`/`escalation` stripped, `routine: false`, `pinned: false`) **then** the original rolled forward, still open, `completedAt` nil |
| Repeating | Next-occurrence row (new id, open, advanced due date) **then** this one marked completed |
| One-off | Marked completed — unchanged from before |

Recurrence and escalation are read out of the row's raw JSON via new typed accessors on
`JSONVal` (`stringValue` / `boolValue` / `intValue`), each returning nil on the wrong shape so a
malformed field degrades to a plain completion rather than a made-up date.

### Write ordering is deliberate

The new row goes up **first**; the completion is skipped entirely if that write fails
(`upsert` now returns `Bool`). Worst case is a duplicate open occurrence — visible and fixable.
The alternative failure mode is a routine that silently stops forever, which is the bug itself.

### Two gaps the widget still cannot close

Both self-heal on the next app launch, so neither is a correctness loss:

1. **The new occurrence's local notification isn't scheduled.** An extension's
   `UNUserNotificationCenter` is its own, not the app's. `NotificationManager.reschedule()`
   rebuilds every alert from the store when the app next syncs.
2. **A linked prep reminder doesn't move** (Buy Ginger Shot Ingredients → Make Ginger Shots).
   `NudgeStore.refresh()` calls `syncPrepReminders()` after every pull.

Worth knowing given the routines run every 2–7 days and Nudge is opened daily.

## Verification done in Cowork

`verify_engine.py` ports **both** the old NudgeStore algorithm and the new engine algorithm to
Python and diffs them across Noah's real reminder records plus ten synthetic edge cases
(monthly-on-the-31st, leap-day yearly, hourly, series past its end date, escalation phases all
expired, missing due date, unknown frequency), at four different clock times including the night
of the bug and a year boundary. Timezone Asia/Tokyo.

**324 comparisons, zero mismatches.** The refactor is behaviour-preserving.

Sanity output for the reminders in the report (interval 2 because Epiduo's first escalation
phase, every 3 days until 26 Jun, has expired, leaving the open-ended every-2-days phase):

```
Epiduo Night        kind=routine  interval=2  keeps its 21:00 evening slot
KP Body Scrub Night kind=routine  interval=2  keeps its 21:00 evening slot
Make Ginger Shots   kind=routine  interval=7  keeps its 17:00 slot
```

Not yet done, and it needs a Mac: **compiling**. Cowork cannot build Xcode projects. See the
Claude Code prompt.

## Files changed

```
NEW  ios/Nudge/Shared/RecurrenceEngine.swift
MOD  ios/Nudge/Shared/CompleteReminderWidgetIntent.swift
MOD  ios/Nudge/Nudge/NudgeStore.swift
MOD  ios/Nudge/Nudge/Models.swift
MOD  ios/Nudge/Nudge.xcodeproj/project.pbxproj   (file added to BOTH targets)
```

`project.pbxproj` was edited by hand — `Shared/` is a real group, not a synchronized one, so new
files there need explicit registration. Structural check passed: every build-file ref resolves,
every fileRef is declared, braces balanced. New IDs are `FE02000000000000000000B1/B2/B3`,
following the manual-entry convention already in the file.

## On-device test plan

1. Make a throwaway daily repeating reminder due today, complete it **from the widget**.
   Expect: it disappears and a new open copy exists for tomorrow.
2. Open the app, confirm the completed one is in Completed and the new one is in Today/Upcoming.
3. Tap a real routine (Epiduo or KP) from the widget on a night it is genuinely due.
   Expect: a completed history entry for tonight **and** the routine itself open at its next
   night, 21:00, still marked routine with its escalation intact.
4. Confirm no duplicate history entries and that Done-today counts it exactly once.
5. Airplane mode: tap a routine. Expect nothing changes — no completion, no snapshot.

Step 3 is the one that actually proves the bug is fixed. Steps 4 and 5 are the ones most likely
to surface a regression.

## Security review

No new surface. Same anon key + user bearer token from the shared Keychain, same RLS-protected
`reminders` table, no service-role key. The inserted rows deliberately omit `user_id` — the
column defaults to `auth.uid()` and RLS pins it, exactly as the app's own writes do, so a row
written from the widget cannot land on another user. No secrets touched, logged, or added.
