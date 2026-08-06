# Claude Code prompt — 2026-08-05: build, test, commit and push the widget recurrence fix

Copy everything below the line into Claude Code, run from the repo root.

---

Work in `~/Claude/nudge` (or wherever this repo lives locally).

## Context

Cowork has already written a complete fix. **Do not redesign it, and do not rewrite the
approach.** Your job is: make it compile, verify it, commit it, push it.

The bug: completing a recurring reminder from the Today widget marked it permanently complete
instead of rolling it forward. Noah hit this on 4 Aug with "Epiduo Night" and "KP Body Scrub
Night". Full write-up in `HANDOFF_2026-08-05_widget-recurring-completion.md` — read it first.

The fix: a new `ios/Nudge/Shared/RecurrenceEngine.swift` compiled by both the app and the widget
extension, holding all the repeat/routine date maths. `NudgeStore` now delegates to it, and
`CompleteReminderWidgetIntent` uses it to spawn the next occurrence (or roll a routine forward
and write a history snapshot) instead of just setting `completed = true`.

## CRITICAL — protect the uncommitted work

There are uncommitted Cowork edits in the working tree. **Do NOT run `git checkout`,
`git restore`, `git stash`, `git clean`, or `git reset --hard` on any of these paths under any
circumstances.** This has destroyed Cowork work in this repo before.

```
ios/Nudge/Shared/RecurrenceEngine.swift              (new, untracked)
ios/Nudge/Shared/CompleteReminderWidgetIntent.swift  (modified)
ios/Nudge/Nudge/NudgeStore.swift                     (modified)
ios/Nudge/Nudge/Models.swift                         (modified)
ios/Nudge/Nudge.xcodeproj/project.pbxproj            (modified)
HANDOFF_2026-08-05_widget-recurring-completion.md    (new)
CLAUDE_CODE_PROMPT_2026-08-05_widget-recurring-completion.md (new)
```

Before you touch anything, run `git status` and confirm all seven are present. If any are
missing, **stop and tell Noah** rather than proceeding.

## Steps

1. **Read** `HANDOFF_2026-08-05_widget-recurring-completion.md`, then
   `ios/Nudge/Shared/RecurrenceEngine.swift` and the diff of
   `ios/Nudge/Shared/CompleteReminderWidgetIntent.swift`.

2. **Build both targets.** `project.pbxproj` was hand-edited to add `RecurrenceEngine.swift`
   to the app target *and* the `NudgeWidgets` extension target — the build is the real test of
   that edit.

   ```
   xcodebuild -project ios/Nudge/Nudge.xcodeproj -scheme Nudge \
     -destination 'generic/platform=iOS' build
   ```

   Likely failure points, in order of probability:
   - `nonisolated struct Rule` / `nonisolated enum CompletionKind` inside a `nonisolated enum`.
     The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the annotations are
     there so the nested types stay reachable from the widget intent's non-isolated
     `perform()`. `Shared/WidgetPendingCompletionStore.swift:33` is the precedent that this
     spelling is accepted. If the compiler rejects it, fix the isolation — do not delete the
     types.
   - Optional-chaining shapes like `row["routine"]?.boolValue ?? false`.
   - The pbxproj entries themselves (`FE02000000000000000000B1/B2/B3`). If Xcode reports the
     file is missing from a target, add it through Xcode's UI rather than hand-patching again.

   Fix compile errors minimally. Do not change the logic or the write ordering.

3. **Check the warnings.** This repo was cleaned of warnings on 4 Aug — keep it that way.
   `routineEveningComponents` in NudgeStore is still used by `routineRescheduleTo`, so it should
   not warn as unused; if it does, something else changed and is worth a look.

4. **Install on Noah's iPhone** and have him run the on-device test plan at the end of the
   handoff. Step 3 (tap a real routine from the widget) is the one that proves the fix. Report
   what he sees before committing — if the routine does not roll forward on device, the fix is
   not done and committing it would just bury the problem.

5. **Commit** once it builds and the device test passes. Suggested message:

   ```
   Widget: complete recurring reminders the way the app does

   Tapping a repeating reminder in the Today widget used to set completed = true
   and nothing else, so the series ended there — Epiduo Night and KP Body Scrub
   Night both died this way on 4 Aug. The file's own header claimed the app would
   reconcile routines on next launch; no such reconcile existed for the Supabase
   path (RemindersSync only covers items ticked in Apple Reminders).

   Adds Shared/RecurrenceEngine.swift, compiled by both targets, as the single
   source of truth for repeat and routine dates. NudgeStore delegates to it, so
   the app and the widget cannot drift apart again. The widget now spawns the next
   occurrence for a repeating reminder, and for a routine writes a history snapshot
   then rolls the routine forward with escalation phases honoured.

   The new row is written before the completion and the completion is skipped if
   it fails: a duplicate open occurrence is recoverable, a dead series is not.

   Verified behaviour-preserving against the previous algorithm across 324
   comparisons on real records plus edge cases (see the handoff).
   ```

6. **Push** to `origin/main`.

7. **Clean up locks and stray objects.** After the push completes, remove any leftover or stale
   git locks so the next session starts clean:

   ```
   rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/*.lock
   ```

   Cowork confirmed (again) that its sandbox cannot write to this repo's `.git` — a `git add`
   attempt failed with `unable to unlink ... Operation not permitted` and left a handful of
   `.git/objects/*/tmp_obj_*` files behind. The index was NOT modified, so nothing is corrupt,
   but sweep them up:

   ```
   git prune-packed && git gc --prune=now
   ```

   Then confirm with `git status` that the tree is clean and the push landed
   (`git log --oneline -3`).

## Report back

Tell Noah: whether both targets built, what (if anything) you had to fix, the device test
result, and the commit hash that was pushed.
