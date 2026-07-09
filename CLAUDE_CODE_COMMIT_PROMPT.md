# Prompt for Claude Code — commit & push the bug-audit fixes

Copy everything below the line into Claude Code, run from the repo root (`~/Claude/nudge`).

---

Commit and push the pending bug-audit changes. Do NOT modify any code — the changes are already made and verified.

1. Run `git status` and `git diff --stat`. You should see exactly:
   - `index.html` modified (~+58/−20) — six web bug fixes (recurring-completion full copy, This-Event-Only snapshot fix, undo-restores-snapshot, date-only overdue rule, triage snooze past-time guard, PWA shortcut actions + Notification guard)
   - `BUG_AUDIT_HANDOFF.md` new — full audit handoff for Opus
   - `CLAUDE_CODE_COMMIT_PROMPT.md` new — this file
   If anything ELSE is modified, stop and tell me before committing.

2. Sanity check: `node --check` the extracted script if you want (`sed -n '/^<script>$/,/^<\/script>$/p' index.html | sed '1d;$d' | node --check /dev/stdin`) — it passes.

3. Commit all three files with message:
   `Web bug-audit fixes: recurring copy integrity, This-Event-Only snapshot, undo restore, date-only overdue, snooze guard, PWA shortcuts (+ audit handoff)`

4. Push to the remote.

5. After the commit and push are done, remove any git locks or stale locks (e.g. `.git/index.lock`, `.git/refs/remotes/*/lock` leftovers) so the next session is smooth.
