# Handoff — Notion push: actual fix (property name mismatch)
**Date:** 2026-07-23 (follow-up to `HANDOFF_2026-07-23_notion-push-error-logging.md` same day)
**From:** Cowork session
**To:** Claude Code session

## What happened

The error-logging change from the earlier handoff today did its job — Noah rebuilt, ran the
push, and got back the real error for the first time:

```
Pushed 0, 2 failed: Notion error (400): Completed is not a property that exists.
```

Root cause: Noah had renamed the "Completed" checkbox column in the live Notion database to
"·" (a single middle-dot character) — deliberately, to fix the double-labeling problem where
Notion's checkbox-grouping showed "Completed" as the header on BOTH the done and not-done
groups. `NotionSyncService.swift` still referenced the old name "Completed", which no longer
existed in the schema, so every push failed with a 400.

Verified directly via the Notion connector (`notion-fetch` on the database) — the live schema
today is: `Title` (title), `Due Date` (date), `Notes` (text), `Nudge ID` (text), `Status`
(select: To Do/Done), and a checkbox literally named `"·"`.

## Decision (confirmed with Noah)

There is only ONE completion field now, not two. Noah confirmed the `·` checkbox alone is
sufficient — Notion's checkbox group header shows a ticked/unticked icon instead of repeating
the property name, so it doesn't have the "Completed" double-labeling problem that `Status`
was originally invented to route around. `Status` is therefore redundant and has been dropped
from the push entirely, alongside the old broken `"Completed"` reference.

**This was a live back-and-forth during the session** — the code briefly went through three
states (send "Completed" → broken; send only "Status", drop checkbox → user corrected, wanted
checkbox not Status; send only "·" checkbox, drop Status → final, confirmed). Only the final
state matters; mentioning the intermediate states here only so it's not surprising if seen in
diff history within this session's conversation.

## What changed (code, uncommitted)

`ios/Nudge/Nudge/NotionSyncService.swift`, `properties(for:listName:)`:
- Removed the `"Completed"` key entirely (was broken — property doesn't exist under that
  name anymore).
- Removed the `"Status"` key (redundant now — see decision above).
- Added `"·": ["checkbox": r.isCompleted]` — this exact string, including the character, must
  match the live Notion property name. If Noah renames this checkbox again in the future, this
  line breaks again with the same class of 400 error; there's a code comment flagging this.

No other properties changed. `Title`, `Due Date`, `Notes`, `Nudge ID` are unaffected.

The earlier same-day logging change (see `HANDOFF_2026-07-23_notion-push-error-logging.md`) is
still in place and should stay — it's what made this diagnosable at all, and will help if this
breaks again for a different reason.

## What you need to do

1. Build the project. This diff is small — a doc comment rewrite plus 3 lines of actual logic
   change in one function.
2. Test: push a reminder (Study list or "Push to Notion" toggle, out of date), confirm it
   succeeds (toast should say "Pushed N to Notion", not a failure). Then check in Notion that
   the row's checkbox (`·` column) reflects the reminder's completion state correctly, and that
   no `Status` value gets written/updated anymore (existing `Status` values in Notion, if any,
   are left alone — Nudge just stops touching that column going forward).
3. Push again with no changes — confirm "Nothing new to push" and no duplicate row (dedupe by
   Nudge ID still applies, untouched by this fix).
4. Toggle a reminder's completion in Nudge, push again — confirm the `·` checkbox updates on
   the same row in Notion.
5. Commit with a message like "Notion push: fix property name mismatch (·, not Completed);
   drop redundant Status field" and push.
6. At the very end, after committing and pushing, remove any locks or stale locks so the repo
   is clean for next time.

## Not in scope here

- No change to push scope (Study list / toggle), incremental logic, or dedupe-by-Nudge-ID.
- The `Status` select property itself is NOT being deleted from Notion by this change — it's
  just no longer written to. If Noah wants it removed from the Notion table entirely, that's a
  manual step in the Notion UI, not something this code change does.
