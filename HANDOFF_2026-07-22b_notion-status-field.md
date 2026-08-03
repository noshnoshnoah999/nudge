# Handoff — Notion push: Status field + schema cleanup
**Date:** 2026-07-22 (same day, follow-up to the earlier Notion push handoff)
**From:** Cowork session
**To:** Claude Code session

## Context

Earlier today, a Cowork session built the manual Notion push feature (already committed,
`2cf6b1a`). After that, Noah made two more requests in the same session:

1. He deleted the `List` and `Location` columns from the "To Do List" Notion database
   himself (not something this session did).
2. He asked for a `Status` select property ("To Do" / "Done") so the database view could
   group active vs. completed reminders with real, readable group names — Notion's
   checkbox-grouping shows the property name ("Completed") as the label for BOTH groups,
   which reads confusingly as if everything is complete.

## What changed (code)

`ios/Nudge/Nudge/NotionSyncService.swift` — in `properties(for:listName:)`:
- Removed the `"List"` and `"Location"` keys from the push payload (Notion would silently
  drop them anyway since those columns no longer exist, but sending dead fields is pointless
  and worth cleaning up).
- Added `"Status": ["select": ["name": r.isCompleted ? "Done" : "To Do"]]`, sent on every
  push alongside the existing `"Completed"` checkbox (kept, not removed — only List/Location
  were dropped).

This is **not yet committed** — `git status` shows `NotionSyncService.swift` as modified.

## What changed (Notion, not code — for your awareness, not action)

- Added a `Status` select property (options "To Do" / "Done") to the To Do List database
  schema.
- Backfilled the 6 existing rows' `Status` from their existing `Completed` value.
- Changed the database's default view to group by `Status` instead of `Completed`, so group
  headers read "To Do" / "Done" instead of both saying "Completed".

## Important — please verify before doing anything else

While doing this Notion-side schema work, the `Status` property disappeared unexpectedly at
least twice during the session — once after a routine `ADD COLUMN` DDL call, and Noah also
mentioned separately that he "accidentally removed" it. It was re-added and re-verified
working as of this handoff, but the Notion API/DSL tooling used this session proved
intermittently unreliable on schema edits (a `RENAME COLUMN` call also failed once with a
DSL parse error). **Do not assume the Notion schema matches what's described above — verify
it directly** (fetch the database, confirm `Status`, `Completed`, `Due Date`, `Notes`,
`Nudge ID`, `Title` are all present) before testing a push, and re-add `Status` as a select
property with options "To Do"/"Done" if it's missing.

## What you need to do

1. Verify the Notion "To Do List" database schema matches what's described above (see note
   just above — don't skip this).
2. Build the project — this Swift change is small (removed 2 dict keys, added 1) but hasn't
   been compiled since the edit.
3. Test: push a reminder, confirm in Notion that `Status` is set correctly ("To Do" or
   "Done" matching the reminder's completion state) and that no request errors occur from
   the missing List/Location properties (they should simply not be sent anymore — confirm
   the push doesn't still reference them anywhere).
4. Commit with a clear message (e.g. "Notion push: drop List/Location, add Status field for
   grouping") and push.
5. **At the very end, after committing and pushing, remove any locks or stale locks** so the
   repo is clean for next time.

## Reminder — scope is still unchanged

Same rule as before: only reminders in the "Study" list, or individually toggled "Push to
Notion", are ever sent — never the full reminder list. Nothing in this follow-up work changes
that.

## Not in scope here — do not build

Noah asked about two-way sync (completing a reminder in Notion also completing it in Nudge,
and vice versa). This was explicitly deferred — it needs a real design pass (sync trigger,
conflict resolution rule, which fields sync back) before any code is written. Do not
implement any Notion→Nudge sync as part of this handoff.
