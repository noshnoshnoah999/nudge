# Claude Code prompt — 2026-11-12 — "See more" notification action (Mac)

Commit `11611d6` is already made locally (by Cowork). Your job: clear locks, build, install, push, commit the docs.

IMPORTANT: Do NOT run `git checkout`, `git restore`, `git stash`, `git reset` or `git clean`. Do not discard or modify any uncommitted work you did not create.

## Steps
1. In `~/Claude/nudge`, remove stale git locks left by Cowork (only if no git process is running): `.git/HEAD.lock`, `.git/index.lock`, `.git/objects/maintenance.lock`, and any `.git/objects/*/tmp_obj_*` files.
2. Confirm `git log --oneline -1` shows `11611d6 Notifications (Mac): add "See more" action for long reminder titles`.
3. Build and install on BOTH iPhone and Mac with `./reinstall_nudge.sh`. Check its output honestly — if either install fails (e.g. provisioning), report the real error, do not report success.
   - If the build fails on a concurrency error in `Notifications.swift` (the new `nonisolated static let` constants or the `SEE_MORE` branch in `didReceive`), report the exact error rather than guessing a fix.
4. Commit these two docs: `CLAUDE_CODE_PROMPT_2026-11-12_see-more-notification.md` and `HANDOFF_2026-11-12_see-more-notification.md`.
5. `git push`.
6. After committing and pushing, remove any locks or stale locks (`.git/*.lock`, `.git/objects/maintenance.lock`) so the next session starts clean.

## What changed (for context)
- `Notifications.swift`: new category `NUDGE_REMINDER_LONG` = Complete / Snooze 1 hour / Reschedule… / See more. `category(forTitle:)` returns it only on Mac Catalyst when the title is 45+ chars; iPhone always gets the old category.
- `didReceive`: `SEE_MORE` re-posts the same notification (same id, silent, `trigger: nil`) with the full title at the top of the body and the plain category. Never reaches `handle()`, never opens the app.
- `LocationMonitor.swift`: geofence notifications use the same rule.

## Test for Noah (Mac)
1. Make a reminder with a long title (45+ chars), due in 2 minutes. Quit or background Nudge.
2. When it fires, Options should list Complete, Snooze 1 hour, Reschedule…, See more.
3. Tap See more → the banner should come back with the full title in the body. Note: does the Nudge window come to the front? (It shouldn't.)
4. Short-title reminder → no See more. iPhone → no See more.
