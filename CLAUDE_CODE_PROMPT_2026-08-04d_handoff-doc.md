# Claude Code prompt — 2026-08-04d: commit the final handoff doc

Short session. Documentation only, no code.

---

1. `rm -f .git/index.lock` first.
2. **Do not run `git checkout` / `git restore` / `git stash` / `git clean` on tracked files.**
   If the tree has changes you did not expect, stop and report them.
3. Do not `git add -A`. Stage explicitly.

## What changed

`HANDOFF_2026-08-04_widget-refresh-and-notification-crash.md` — added a FINAL STATUS block at
the top. The body still described the state mid-session ("needs build + on-device test"), which
is now wrong and would mislead the next reader. The new block records the seven commits, the
confirmed-working status, the residual low-priority checks, and — most importantly — why
`NudgeSceneDelegate` and `pendingColdTap` must not be deleted.

## Tasks

1. `git status` — expect exactly one modified file:
   `HANDOFF_2026-08-04_widget-refresh-and-notification-crash.md`. Anything else → stop and report.
2. Also add the two prompt files from this session if they are still untracked:
   `CLAUDE_CODE_PROMPT_2026-08-04b_crash-fix-and-warnings.md`
   `CLAUDE_CODE_PROMPT_2026-08-04c_text-warning-and-comments.md`
   `CLAUDE_CODE_PROMPT_2026-08-04d_handoff-doc.md`
3. Commit:

```
Close out the 2026-08-04 handoff: all seven commits confirmed on device

The handoff body still read "needs build + on-device test", which was true
when written and misleading now. Added a final status block recording the
seven commits, Noah's on-device confirmation on iPhone and MacBook, the
0-warning build, and the two residual low-priority checks.

Also records the reason NudgeSceneDelegate and pendingColdTap must not be
removed: the UN delegate is attached from SwiftUI's .task, after
didFinishLaunching returns, so UNUserNotificationCenter will not deliver a
launch tap to it. Deleting them breaks cold-launch notification taps
silently, with no crash to point at it.

And the process lesson: the crash survived five attempts because each one
fixed where the work started rather than where the method returned. Five
crash reports settled it in minutes.
```

4. Push to `main`.
5. **Remove any git locks or stale locks** (`.git/index.lock`, `.git/refs/heads/*.lock`) and
   confirm `git status` is clean before finishing.
