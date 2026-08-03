# Claude Code prompt — Siri Shortcuts phrase fixes (2026-07-24c)

## Context
Cowork edited `ios/Nudge/Nudge/NudgeIntents.swift` only — the `NudgeShortcuts`
AppShortcutsProvider phrase list. No intent logic changed, no other files touched
by this session.

Changes made:
1. `AddReminderIntent` — added phrase "Add to Nudge"
2. `WhatsDueTodayIntent` — added "Nudge status" as the lead phrase. Noah confirmed
   on-device that typing "What's due in Nudge" to Siri opened Calendar instead of
   the app (Siri's Calendar/Reminders domain is winning the match). Old phrases
   kept as aliases in case they work in other contexts, but "Nudge status" is now
   the recommended phrase to actually use.
3. `SnoozeReminderIntent` — registered with phrase "Snooze a Nudge reminder"
   (existed in code since intents were first written, was never in the
   AppShortcutsProvider list, so Siri could never trigger it)
4. `QuickCatchIntent` — registered with phrase "Nudge it" (previously only
   reachable via the Control Center button)

Verified against Apple's documented limits: max 10 AppShortcut entries per app
(we're at 6), max 1000 phrases total (nowhere close). Not a constraint issue.

## What I need you to do

1. **Build the Nudge iOS target first**, don't skip this — Cowork cannot run
   Xcode, so this diff has not been compile-checked. If it fails to build, fix
   only what's needed to make `NudgeIntents.swift` compile (do not touch other
   files' logic).

2. **Do NOT commit** `ios/Nudge/NudgeWidgets/NudgeWidgets.swift` or
   `ios/Nudge/NudgeWidgets/TodayWidgetStyle.swift` as part of this commit —
   those are modified from an earlier, separate session (widget tap-complete +
   styling work) and are unverified/not part of this change. Check `git status`
   and `git diff` on those two files before committing anything — if they're
   still sitting there modified, leave them out of this commit (stage only
   `NudgeIntents.swift`) so the two pieces of work don't get tangled together.
   Tell Noah at the end that those two files are still pending separately.

3. Commit **only** `ios/Nudge/Nudge/NudgeIntents.swift` with a message like:
   `Siri Shortcuts: fix What's Due Calendar collision, add "Add to Nudge", wire up Snooze + Quick Catch phrases`

4. Push to origin/main.

5. **After committing and pushing, remove any locks or stale locks** so the
   next session starts clean.

## Testing note for Noah (include in your final summary to him)
After this is on-device (next TestFlight/Xcode build), Siri phrases need
re-indexing — this can take a little time or a device restart to pick up new
AppShortcut registrations. Ask him to test all four wired phrases once built:
"Add to Nudge", "Nudge status", "Snooze a Nudge reminder", "Nudge it" — and
specifically re-test whether "Nudge status" avoids the Calendar collision that
"What's due in Nudge" hit. If "Nudge status" ALSO loses to a system domain,
that's a structural Siri priority issue, not a phrase-wording one, and will
need a different approach (report back rather than guessing at another phrase).
