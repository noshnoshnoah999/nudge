# Handoff — Notion workspace change affecting your study-schedule task
**Date:** 2026-07-22
**From:** Nudge Cowork project
**To:** Schoolwork/study-data Cowork project

## Why you're getting this

You have a scheduled task that reads Noah's study data and writes his daily schedule into a
Notion database called **"TIHS Daily Study Plans"**. That database's location in Notion's
page hierarchy changed today as a side effect of unrelated work in the Nudge project. This
doc tells you exactly what changed so you can verify your task is unaffected.

## What changed

- A new top-level Notion page called **"TIHS"** was created
  (id `3a574319-20b8-8191-96a7-f045fc325c6c`).
- The existing **"TIHS Daily Study Plans"** database was moved to become a child of that new
  TIHS page. Previously it had no visible parent (effectively a top-level/private database).
- A new, unrelated database called **"To Do List"** was created alongside it, also under
  TIHS. That one is for a separate Nudge feature (manual reminder push) and has nothing to do
  with your study-schedule pipeline — mentioned only for completeness.

## What did NOT change

- **"TIHS Daily Study Plans"` database ID: `79ed206d-9712-4c4f-9008-809eec3c1c3b`** — unchanged.
- **Its data source ID: `collection://9bb0637e-fd81-4e35-9359-321bb4e8056c`** — unchanged.
- Its schema (Day, Date, Day Type, Graduation Pace, Status, StudyTrack Push, Subjects) —
  unchanged, not touched.
- Moving a Notion database to a new parent page changes only where it appears in the
  sidebar/hierarchy — it does not change the database ID or data source ID. Any integration
  or API call that references the database by ID (which is the normal way Notion API
  integrations work, not by folder path) should be completely unaffected.

## What to verify

If your scheduled task writes to this database by ID (the standard approach), you likely need
to do nothing. But please confirm rather than assume:

1. Check whatever code/config your scheduled task uses to target the database — confirm it
   references the ID above, not a URL path or a "search by title" lookup that could resolve
   to something unexpected now that there's a page also named similarly nearby.
2. Let the task run on its next normal schedule (or trigger it manually if you can) and
   confirm the write still lands in the right place with the right data.
3. If it uses Notion's search-by-title rather than a fixed ID to find the database each run,
   double check it doesn't get confused — the new "TIHS" page and "To Do List" database are
   nearby in the workspace now and share the "TIHS" naming.

## Who to ask

Noah — he can also just open the "TIHS" page in Notion and confirm visually that "TIHS Daily
Study Plans" and "To Do List" are both showing as children of it, which is the intended end
state.
