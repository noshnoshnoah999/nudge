Paste this into Claude Code (in the Nudge repo):

---

Read `handoffs/2026-07-15-payday-card-filter.md` for context.

I (Cowork) already edited `ios/Nudge/Nudge/NudgeStore.swift` — `buyReminders()` now filters Shopping-list reminders to only those due on payday (via existing `Payday.inMonth(Date())` logic), instead of returning the whole Shopping list. `ContentView.swift` needed no changes.

Please:
1. Build the iOS app (Xcode build, no simulator run needed) and confirm there are no compile errors from this change.
2. If it builds clean, `git add`, commit with a clear message (e.g. "Fix Pay Day card to only show reminders due on payday, not entire Shopping list"), and push.
3. If it does NOT build clean, report the exact error back — do not attempt to guess-fix beyond what's needed to resolve a straightforward compile error; if the fix isn't obvious, stop and report.
4. After committing and pushing successfully, remove any Git locks or stale locks (e.g. `.git/index.lock` if present) so the next session starts clean.

Do not touch anything else in the repo.
