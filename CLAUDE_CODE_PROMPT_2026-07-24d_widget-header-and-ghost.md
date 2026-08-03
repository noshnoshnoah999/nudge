# Claude Code Prompt — Widget header removal + ghost "savings check-in" — 2026-07-24d

## Part A — Widget header removal (code, already edited in Cowork)

File: `ios/Nudge/NudgeWidgets/NudgeWidgets.swift`, `TodayWidgetView.body`.

Removed the top HStack containing the `"Today"` title and the `"\(entry.overdue) overdue"` capsule pill. The widget is now a pure Dumb-Phone list with no header chrome. (The pill also showed as a grey blob under Apple's tinted home-screen mode.) The failed/empty state branches were left untouched.

Braces/parens verified balanced.

1. Build the widget target to confirm it compiles.
2. Commit: `feat(widget): remove Today header + overdue pill (pure list, no chrome)`
3. Push.

## Part B — Ghost "savings check-in" reminder (DATA, needs investigation)

**Symptom:** The Today widget shows a reminder titled roughly "💰 savings check-in — ..." that Noah says was deleted from the Nudge app ages ago and no longer appears there. It still shows in the widget.

**What I found from Cowork (read-only):**
- There is NO hardcoded "savings check-in" string anywhere in `ios/` — it is not a sample/seed.
- Commit `3046bb3` = "Connect Finance integration (savings-goal check-in + one-off expense reminders)". This feature likely CREATED a "savings check-in" reminder row in Supabase.
- The widget reads Supabase directly (per `NudgeFeed.fetch()` / `NudgeProvider.build()`), so if the row still exists in the DB, the widget will show it even if the app UI filters it out.

**Hypothesis:** the row still exists in the Supabase `reminders` table (created by the Finance integration, never hard-deleted — maybe only soft-dismissed or removed from a UI list, not the DB).

**Your job — investigate, do NOT delete blind:**
1. Query the Supabase `reminders` table for any row whose title contains "savings check-in" (case-insensitive). Also check for `completed`/`dismissed` flags and `dueDate`.
2. Report to Noah what you find BEFORE deleting anything — confirm it's the ghost and not a live reminder he wants.
3. Also check whether the Finance integration (commit 3046bb3) has any code that RE-CREATES this reminder on a schedule/launch — if so, deleting the row alone won't stop it recurring; the recreating logic needs disabling too. Noah said this feature was "got rid of ages ago", so confirm it's actually removed and not still inserting rows.
4. Once confirmed with Noah, delete the ghost row(s) from Supabase.

**Safety:** This touches the live reminders table. Do a targeted delete by exact row id after showing Noah the matching row(s). Do not bulk-delete on a title LIKE match without confirmation.

## After both parts

Remove any git locks / stale locks (`.git/index.lock`, `.git/*.lock`) so the next session is smoother.
