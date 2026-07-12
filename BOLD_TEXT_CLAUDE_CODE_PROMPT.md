# Claude Code Prompt — Commit & Push Bold Text Feature

Copy-paste the block below into Claude Code (run from the Nudge repo root).

---

Commit and push the Bold Text feature. Three files were changed in Cowork:
- `ios/Nudge/Nudge/AppSettings.swift`
- `ios/Nudge/Nudge/SyncSettingsView.swift`
- `ios/Nudge/Nudge/NudgeApp.swift`
- (plus new docs `BOLD_TEXT_HANDOFF.md` and this prompt)

Do the following, in order:

1. Run `git status` and `git diff` to review the changes before committing. Confirm they only add a `boldText` preference, a "Bold text" toggle in the Appearance section, and a root-level `.environment(\.font, ...)` override. Nothing else should be touched.
2. Stage and commit with message:
   `Add Bold Text setting (iOS/macOS) — root env font override + Appearance toggle`
3. Push to the remote.
4. After pushing, remove any git lock files if present so the next session is clean:
   `rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true`
   (Only remove locks — do not touch anything else.)
5. Confirm the push succeeded and report back.

Before you commit, if the Swift toolchain is available, optionally build the iOS scheme to confirm it compiles. If it doesn't build, stop and report the error instead of committing.
