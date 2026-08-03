# Prompt for Claude Code

Read `HANDOFF_2026-07-23_notion-push-error-logging.md` in this repo for full context, then:

1. Build the Nudge project (iOS target). Confirm it compiles cleanly — the diff is small
   (`ContentView.swift` and `NotionSyncService.swift`, ~30 lines total) and only adds error
   logging/surfacing, no logic changes.
2. Run it (device or simulator) with the Xcode console visible. Trigger a Notion push (tap the
   header push button) with at least one reminder in the "Study" list or individually toggled
   "Push to Notion" and out of date.
3. Read the actual Notion failure reason — either from the new `[Notion] push FAILED for
   "...": <message>` console line, or the updated toast text (now includes the real error,
   held on screen for 7s instead of 3s when there's an error to read).
4. Report the real error back before attempting any further fix — do not guess. The obvious
   causes (Xcode target membership, Notion schema, integration connection) were already ruled
   out this session; see the handoff doc for how each was checked.
5. Commit with message: "Notion push: log and surface real failure reason instead of a bare
   count" — and push to origin/main.
6. At the very end, after committing and pushing, remove any locks or stale locks in the repo
   (e.g. check for a leftover `.git/index.lock`) so the repo is clean and smooth for next time.

Do not implement a fix for the underlying Notion failure in this pass — only get the build
building, get the real error message, and report it back. The actual fix depends entirely on
what that error says.
