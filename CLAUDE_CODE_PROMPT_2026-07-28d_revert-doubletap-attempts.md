# Claude Code prompt — 2026-07-28d: commit the revert of the double-tap bug hunt

**Copy everything below the line into Claude Code.**

---

## Your task

Commit and push a revert. **No behaviour changes, no fixes, no new code.**

The user called off the double-tap-to-select bug hunt after five failed attempts. All app code has
already been restored to its pre-hunt state in the working tree. Your only job is to commit that and
push it.

1. `git status` and `git diff` to confirm what's there.
2. Verify the revert is exact: `git diff f300851 -- ios/` should print **nothing**. If it prints
   anything, stop and report — do not commit.
3. Commit the two modified Swift files.
4. Push.
5. Remove stale locks and finish.

Suggested commit message:

```
revert(ios): restore AddReminderView to pre-double-tap-hunt state

Reverts d2cd909. Five attempts to fix intermittent double-tap-to-select
in the reminder title all failed on-device; none of them changed the
behaviour, so the code goes back to where it started rather than
carrying dead workarounds. Bug is unresolved and documented.
```

## What's in the working tree

**Modified — both restored byte-for-byte to commit `f300851`, the last commit before the bug hunt:**

- `ios/Nudge/Nudge/AddReminderView.swift` — back to the original `TextField(axis: .vertical)` fields
  with their `simultaneousGesture` tap-to-focus assists, `@FocusState` bindings, and
  `.scrollDismissesKeyboard(.interactively)`.
- `ios/Nudge/Nudge/Changelog.swift` — back to 2.29. The v2.30 entry claiming this bug was fixed is
  gone, because it wasn't.

**Deleted:** `ios/Nudge/Nudge/GrowingTextView.swift` (the `UITextView` rewrite — never worked, never
committed).

**Already clean, do not touch:** `NudgeApp.swift` — its diagnostic `init()` was reverted earlier and
it currently matches HEAD.

**Keep, do not revert:** the correction banner at the top of `TITLE_FIELD_BUG_HANDOFF.md` (committed
in `d2cd909`). The commit being reverted is the code, not the documentation. That banner records that
the file's original diagnosis is wrong, and removing it would let a future session repeat the same
dead end.

## Do not "helpfully" retry the fix

Five approaches were tried and measured on-device. Every one failed. Do not attempt a sixth, and do
not leave any partial workaround in place:

1. Gating the tap-to-focus `simultaneousGesture` on `!isFocused` — partial at best.
2. Removing that gesture entirely — regressed the keyboard not opening at all.
3. Moving tap-to-focus behind the field via `.background(...)` (commit `d2cd909`) — no change.
4. Disabling `UIScrollView.delaysContentTouches` **and** `.scrollDismissesKeyboard(.never)` together
   — **0/10**. Cleared the enclosing `ScrollView`.
5. Replacing the field with a `UIViewRepresentable`-wrapped `UITextView` — still failed.

A sixth idea was written but never built or tested: `.interactiveDismissDisabled()` on the sheet, on
the theory that the sheet's presentation-level drag-to-dismiss pan recognizer tracks touches across
all its content. **That is not in the working tree and should not be added.** It is recorded only so
the next person knows it's untested rather than ruled out.

## Known state of the bug (leave it documented, not fixed)

Double-tapping a word in the reminder title or notes does not reliably select it. Intermittent,
uncorrelated with title length, new-vs-existing reminder, or focus state. **iPhone only** — Mac
Catalyst is fine, and double-tap works correctly in Apple Notes on the same iPhone, so it is specific
to Nudge and not a device setting.

`TITLE_FIELD_BUG_HANDOFF.md`'s line-count diagnosis is wrong and its correction banner says so.

## Housekeeping

- Commit only the revert. Nothing else.
- Push once committed.
- **Remove any stale lock files at the end** — `.git/index.lock` and `ios/Nudge/.git/index.lock`.
  One stale `.git/index.lock` was already cleared during this session; check again after pushing.

No API keys, secrets or user data involved.
