# Claude Code prompt: push the Sonnet 5.5 model switch

Context: commit ed2aae9 changes `AIScheduler.defaultModel` from "claude-sonnet-4-6" to "claude-sonnet-5-5".
That one constant drives all AI features (Smart Reschedule, Quick Catch, end-of-day carry-over, AI grouping, Scan Reminders).

Safety: do NOT run git checkout, restore, stash or clean. `ios/Nudge/Nudge.xcodeproj/project.pbxproj` has uncommitted changes that must be left alone.

Steps:
1. `git log --oneline -3` and confirm ed2aae9 is present.
2. `git push` (do not force).
3. Build the iOS app and the Mac app to confirm they still compile.
4. At the very end, after committing and pushing, remove any stale git locks so the next session is smooth:
   - delete `.git/*.lock`, `.git/objects/maintenance.lock`, `.git/refs/**/*.lock`, and `.git/objects/*/tmp_obj_*` if no git process is running;
   - also delete any `.git/stale-*` files and `.git/stale-tmp/` left by Cowork.
   - confirm with `git status`.
