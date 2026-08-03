# Handoff — Notion push: surface real failure reason
**Date:** 2026-07-23
**From:** Cowork session
**To:** Claude Code session

## Context

Noah reported the Notion push has been failing ("Pushed 0, N failed" toast). Investigation
this session ruled out the two most likely causes:

1. **Xcode target membership** — checked `Nudge.xcodeproj/project.pbxproj`. This project uses
   Xcode 16's `PBXFileSystemSynchronizedRootGroup` (file-system-synchronized groups), so any
   `.swift` file physically in the folder is automatically part of the target. No manual
   target-add step needed — the concern raised in the original `HANDOFF_2026-07-22_notion-push.md`
   about this doesn't apply to this project's Xcode version. Not the cause.
2. **Notion schema drift** — checked live via Notion's Property Visibility panel on the "To Do
   List" database. `Status`, `Nudge ID`, `Notes`, `Completed`, `Title`, `Due Date` all exist —
   `Status` and `Nudge ID` and `Notes` are just hidden from the default table view, which
   doesn't affect the API. Not the cause.
3. **Integration not connected** — checked via "..." → Connections on the database. The
   "Nudge" integration is listed as an active connection with Can read/insert/update content.
   Not the cause.

So the actual failure reason is still unknown — the app's own code throws it away. In
`NotionSyncService.swift`, every per-reminder failure was caught and only counted
(`failed += 1; continue`), never logged or surfaced. The toast could only ever say "N failed,"
never why.

## What changed this session (not yet built or tested)

**`NotionSyncService.swift`:**
- `NotionPushResult` gained a `firstError: String?` field — the error message from the first
  reminder that failed in a given push.
- Added `print("[Notion] ...")` logging for push start, each individual success, each
  individual failure (with the real error message), and the final summary. These will show in
  Xcode's console when running from Xcode.
- On failure, the real error message (`NotionSyncError.errorDescription` if available, else
  `error.localizedDescription`) is now captured into `firstError` instead of being discarded.

**`ContentView.swift`** (`pushToNotion()`):
- When `result.failedCount > 0` and `result.firstError` is present, the toast now reads
  `"Pushed X, N failed: <real error message>"` instead of the old generic
  `"Pushed X, N failed — try again"`.
- Toast hold time extended from 3s to 7s when there's an error to read (either a thrown
  `NotionSyncError`/other error, or a per-reminder failure with a message), so it's actually
  readable before it disappears.

**No logic changes** to what gets pushed, scope filtering, or the incremental/dedupe behavior.
This is purely visibility — same push behavior, just no longer silent about why something
failed. No secrets are logged (token and database ID are never printed; only the reminder
title and Notion's own error message string are logged/shown).

## What you need to do

1. **Build the project** — small diff (two files, ~30 lines), should compile cleanly, but
   hasn't been built since the edit.
2. **Reproduce the failure**: run from Xcode with the console visible, tap the Notion push
   button with at least one Study-list or "Push to Notion"-toggled reminder in scope, and
   read the actual error — either from the `[Notion] push FAILED for "...": <message>` console
   line, or directly from the new toast text.
3. **Report the actual error back to Noah** (and to the next session) so the real fix can be
   scoped. Do not guess at a fix without seeing this — the three most likely causes have
   already been ruled out above, so whatever shows up now is probably something less obvious
   (e.g. a malformed `Due Date` value on a specific reminder, a `Notes` field content Notion
   rejects, a stale/invalid token, or a mismatched database ID in Keychain vs. the actual "To
   Do List" database).
4. **Commit and push.** Suggested message: "Notion push: log and surface real failure reason
   instead of a bare count".
5. **At the very end, after committing and pushing, remove any locks or stale locks** so the
   repo is clean for next time. (Cowork's sandbox hit `unable to unlink .git/index.lock:
   Operation not permitted` this session trying to commit directly — expected, per
   [[nudge-git-commit-limitation]], but worth clearing so it doesn't linger.)

## Not in scope here

- No fix was made to whatever the underlying Notion failure actually is — that requires
  knowing the real error first.
- No change to push scope, schema, or Keychain handling.
