# Prompt for Claude Code

Read `HANDOFF_2026-07-23b_notion-push-fix.md` in this repo root for full context, then:

1. Build the Nudge project (iOS target). Small diff in `NotionSyncService.swift`'s
   `properties(for:listName:)` — removed the broken `"Completed"` key and the redundant
   `"Status"` key, added `"·": ["checkbox": r.isCompleted]` (exact property name in the live
   Notion database — confirmed via the Notion connector this session).
2. Run it and test a real push: mark a reminder in the "Study" list (or toggle "Push to
   Notion") and out of date, tap the header push button, confirm the toast says "Pushed N to
   Notion" (not a failure).
3. In Notion, confirm the pushed row's `·` checkbox column matches the reminder's completion
   state, and that `Status` is no longer being written to.
4. Push again with no changes — confirm "Nothing new to push", no duplicate row.
5. Toggle the reminder's completion in Nudge and push again — confirm the same row's `·`
   checkbox updates (not a new row).
6. Commit with message: "Notion push: fix property name mismatch (·, not Completed); drop
   redundant Status field" — and push to origin/main.
7. At the very end, after committing and pushing, remove any locks or stale locks in the repo
   (check for a leftover `.git/index.lock`) so it's clean for next time.

If the push still fails after this fix, get the real error from the toast/console (error
logging from the earlier same-day commit should still be in place) and report back rather than
guessing further — do not assume this is the only issue without seeing a live success.
