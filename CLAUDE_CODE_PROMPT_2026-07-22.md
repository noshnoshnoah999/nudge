# Prompt for Claude Code — paste this in

Read `HANDOFF_2026-07-22_notion-push.md` in this repo first — it has full context on what
was built, why, and exactly what's left to do. Short version: a Cowork session added a
manual "push schoolwork reminders to Notion" feature (new files `NotionKeyStore.swift` and
`NotionSyncService.swift`, plus edits to `Models.swift`, `NudgeStore.swift`,
`AddReminderView.swift`, `SyncSettingsView.swift`, `ContentView.swift`), AND separately
removed the app's opening/splash animation (`SplashView.swift`, plus a small related edit in
`ContentView.swift`'s launch `.task`). None of it has been compiled, added to the Xcode
target, tested, or committed yet — do both in the same pass.

Please:

1. Add `NotionKeyStore.swift` and `NotionSyncService.swift` to the Nudge target in
   `ios/Nudge/Nudge.xcodeproj` (same target as `APIKeyStore.swift`).
2. Build the project and fix any compile errors you find — this code hasn't been run yet.
3. Sanity-check `NotionSyncService.swift`'s Notion API request shapes are correct for API
   version `2022-06-28` (database query filter, page create/update body).
4. Do NOT change the feature scope. It must stay: only reminders in the "Study" list or
   individually toggled "Push to Notion" get pushed — never the full reminder list. This was
   explicitly corrected once already this session after a misunderstanding; don't reintroduce
   "push everything."
5. Confirm the pre-existing malformed comments in `NudgeStore.swift` (~line 1212, ~1316,
   missing a `/` in `//`) — flagged in the handoff doc, not something to fix unless you think
   it's trivial and safe to do alongside this work. Ask me if unsure.
6. Once it builds clean: commit with a clear message describing the Notion push feature, then
   push to git.
7. **At the very end, after committing and pushing, remove any locks or stale locks** (e.g.
   `.git/index.lock` or similar) so the repo is clean and ready for the next session.
8. Separately: I have an existing scheduled task that writes my daily study schedule into the
   "TIHS Daily Study Plans" Notion database. That database was just moved under a new "TIHS"
   parent page (its ID didn't change, so it should be unaffected) — please just note in your
   summary back to me whether you saw anything that suggests that task needs updating, since
   I want to be safe rather than assume it's fine.

Report back with: what you changed, whether it compiled cleanly, what you tested, and
confirmation the commit/push succeeded with no stale locks left behind.
