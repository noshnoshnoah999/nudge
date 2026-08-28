# Claude Code prompt — commit & push "Next Up" hero fix

## Context
Cowork edited `ios/Nudge/Nudge/ContentView.swift` directly on Noah's Mac at
`/Users/noahflouty/Claude/nudge`. Cowork cannot commit/push to this repo's `.git`
(see project memory `nudge-git-commit-limitation.md`), so that's your job.

Note: the previous "Completed Today section" change is already committed as `4695014`
— nothing to do there. This is a separate, new change on top of it.

## What changed (already done, just needs commit+push)

Bug: the Home tab's "Next Up" hero card (`nextUp` property, ~line 685 in
`ContentView.swift`) picked `store.todayReminders().first`, which sorts earliest-due
FIRST regardless of whether that item is already overdue. Result: if you have an
overdue-today item (e.g. "Talk to Dad" at 15:05, now late) AND a later untouched item
today (e.g. "FaceTime Dad" at 15:15), the hero showed the late one as "STILL DUE" even
though there's a legitimate upcoming item still ahead. Noah wants the upcoming one
shown instead — the late item should only surface once nothing today is still ahead.

Fix: `nextUp` now prefers the earliest item where `!store.isOverdue($0)` (i.e. still
ahead of now); only falls back to `today.first` (which will be the earliest overdue
item) when every item today is already overdue or there's nothing upcoming left.

```swift
private var nextUp: Reminder? {
    let today = store.todayReminders()
    return today.first { !store.isOverdue($0) } ?? today.first
}
```

This is a pure reordering of which single item is chosen — no change to
`nextUpCard`'s rendering (still uses `store.isOverdue(r)` to decide "STILL DUE" vs
"NEXT UP" label/color on whichever item is chosen), no change to `todayReminders()`
or `isOverdue()` themselves, no change to the Today tab list (unaffected — this only
touches the Home hero card's single-item selection).

## Your tasks

1. `cd` into the repo, confirm `git diff ios/Nudge/Nudge/ContentView.swift` matches
   the description above (should be a small diff — just the `nextUp` property and its
   doc comment).
2. Build/typecheck the iOS target to confirm it compiles.
3. If clean, commit with a message like:
   `Home hero: prefer next upcoming today item over an already-passed one`
4. Push to the remote.
5. **After committing and pushing, remove any git locks or stale locks** so the repo
   is clean and smooth for the next session.
6. If the build fails, do NOT force a commit — report the compile error back instead.

## Safety
No secrets, keys, or credentials touched. Standard commit/push only.
