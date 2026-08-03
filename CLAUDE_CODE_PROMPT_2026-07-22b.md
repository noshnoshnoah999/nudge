# Prompt for Claude Code — paste this in

Read `HANDOFF_2026-07-22b_notion-status-field.md` in this repo first. Short version: after
the Notion push feature was committed earlier today (2cf6b1a), I made two more changes in the
same Cowork session: deleted the List/Location columns from the Notion "To Do List" database
myself, and asked for a Status select field ("To Do"/"Done") so the database view groups
active vs. completed reminders with readable names instead of both groups saying "Completed".

`NotionSyncService.swift` was updated to match (drop List/Location from the push payload, add
Status) but is NOT yet committed.

Please:

1. **First, verify the Notion schema directly** — fetch the "To Do List" database and confirm
   it has: Title, Completed (checkbox), Status (select: "To Do"/"Done"), Due Date, Notes,
   Nudge ID. The Status field was flaky during setup (disappeared on its own at least once)
   — if it's missing, re-add it as a select property with those two options before doing
   anything else.
2. Build the project and fix any compile errors — this Swift change hasn't been compiled.
3. Test: push a reminder from the app, confirm in Notion its Status matches its completion
   state, and confirm no errors come from the removed List/Location fields.
4. Do NOT build or start two-way sync (Notion → Nudge). That was explicitly deferred — it
   needs a real design conversation (sync trigger, conflict rule, which fields sync back)
   before any code. If you think it's relevant, ask me, don't build it.
5. Once it builds and tests clean: commit with a clear message and push.
6. **At the very end, after committing and pushing, remove any locks or stale locks** so the
   repo is clean and ready for next time.

Report back with: what you verified in the Notion schema, whether it compiled cleanly, what
you tested, and confirmation the commit/push succeeded with no stale locks left behind.
