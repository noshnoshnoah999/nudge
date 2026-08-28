# Claude Code prompt — 2026-08-27 — "buy" date chips (Today / Tomorrow / Payday)

## Step 0 — clear the stale lock FIRST

Cowork tried to `git add` and could not unlink lock files (the mounted repo denies
unlink on `.git`). There is a stale lock. Before anything else:

```bash
cd ~/Claude/nudge
rm -f .git/index.lock
git status
```

The change to `ios/Nudge/Nudge/AddReminderView.swift` may already be staged. Keep it.

## What changed and why

One file: `ios/Nudge/Nudge/AddReminderView.swift`. Written by Cowork, **not built or
run** — no Xcode in the Cowork sandbox. Your job is to build it, fix anything the
compiler objects to, commit, and push.

### The feature

The existing "buy" keyword rule (`applyBuyRule()`) is unchanged in intent: typing a
title containing the whole word "buy" files the new reminder into **Shopping** and sets
the due date to **the next payday at 09:00** (`Payday.next()` — the 15th, or the Friday
before if the 15th is a weekend).

Noah's request: payday can be 20+ days out, and a cheap purchase doesn't need to wait.
So a chip row now appears **under the title text box**, reading:

> Filed under Shopping — when do you want to buy it?
> `[ Payday · 15 Sep ]  [ Today ]  [ Tomorrow ]`

- The rule still fires instantly and still picks Payday by default — **zero extra taps
  when payday is right.** The chips are an override, not a gate.
- One tap moves the date. The reminder **stays in Shopping** regardless of which chip
  is picked; only the date changes.
- The chips show only for NEW reminders (`editing == nil`) and only once the rule has
  fired (`buyRuleApplied`). Deleting the word "buy" hides them again and re-arms the rule.

### Times

- **Payday** → `Payday.next()`, i.e. 09:00 as always.
- **Tomorrow** → 09:00 tomorrow.
- **Today** → 09:00 today; if that's already past, the next hour (capped at 22:00).
  Either way it goes through `store.nextFreeSlot(_:excluding:)` so it doesn't collide
  with an existing timed reminder. This mirrors the logic already in
  `NudgeStore.recommendedTime`.

### The bug this also fixes (important — please verify this one on device)

`applyBuyRule()` was called a second time inside `save()` (and `saveThisEventOnly()`)
with **no guard**. So the old flow was:

1. Type "Buy socks" → date jumps to next payday
2. Manually set the date to today
3. Tap Save → `applyBuyRule()` runs again → **date silently reverts to payday**

Found by reading the code, never confirmed on device. The fix: the DATE half of
`applyBuyRule()` now runs once only, guarded by `buyRuleApplied`. The `save()` call is
still a genuine safety net for titles that arrive **prefilled** (where
`.onChange(of: title)` never fires), so it was not removed — the LIST half still runs
every time. `.onChange(of: title)` no longer sets `buyRuleApplied` itself; `applyBuyRule()`
owns that flag now.

## What to do

1. Clear the lock (Step 0).
2. `git diff` and read the change.
3. **Build for iOS and Mac Catalyst.** This file has a documented history of Swift
   type-checker timeouts ("unable to type-check in reasonable time") when `body` grows,
   which is why the chip row is a separate `@ViewBuilder private var buyDateChips` and
   the helpers are separate methods. If the type-checker complains anyway, break the
   chip `Button` label into its own small view rather than inlining it back.
4. Things worth a compiler eye:
   - `private enum BuyWhen` is nested inside `AddReminderView`; `ForEach(BuyWhen.allCases)`
     relies on its `Identifiable` conformance.
   - `UIImpactFeedbackGenerator` is used in `setBuyWhen` — same as `applyPreset` already
     does, so Catalyst should be fine, but confirm.
5. **Test on device:**
   - Type "Buy milk" → lands in Shopping, date = next payday, Payday chip highlighted.
   - Tap Today → date moves to today at a sensible future time, Today chip highlights.
   - **Tap Save, reopen the reminder — the date must still be today, not payday.**
     This is the regression fix; if it still reverts, the guard isn't working.
   - Tap Tomorrow → 09:00 tomorrow.
   - Change the date by hand in the "When" section to something else → no chip should be
     highlighted (selection is derived from `due`, not stored).
   - Delete the word "buy" from the title → chips disappear. Retype it → they come back
     and the date resets to payday.
   - Edit an EXISTING reminder whose title contains "buy" → no chips, nothing auto-changes.

## Known edge case (leave as is unless Noah says otherwise)

If payday happens to BE today or tomorrow (i.e. around the 14th/15th), the Today or
Tomorrow chip highlights instead of the Payday chip, because `activeBuyWhen` checks
today/tomorrow first. The date is identical either way — only the highlight differs.

## Then commit and push

```
Buy rule: Today/Tomorrow/Payday chips under the title, and stop save() overwriting a chosen date

The "buy" keyword rule still fires instantly and picks the next payday, but a chip
row now appears under the title box so a small purchase can be pulled back to Today
or Tomorrow in one tap. The list half is unchanged: buy reminders always file into
Shopping.

Also fixes a real overwrite: applyBuyRule() was called again from save() with no
guard, so manually choosing an earlier date silently reverted to payday on save.
The date half now runs once only; the list half still runs every time.
```

Push to `main`.

## Finally — clean up locks

After the commit and push have both succeeded, remove any remaining lock or stale lock
files so the next session starts clean:

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock
git status
```

Confirm `git status` is clean and the push landed.
