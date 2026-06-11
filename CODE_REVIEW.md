# Nudge — Code Review Findings (for Opus to fix)

Scope: mainly the native iOS/Mac app (`ios/Nudge/Nudge/`), some web (`index.html`).
Each item: **what's wrong → where → suggested fix**. Ordered by priority.

---

## P0 — Data integrity

> **Status: all 4 fixed & deployed to Mac 2026-06-11 (iPhone pending — not connected).**
> Paused here per plan so the sync can be tested on a real edit before P1/P2.

### 1. ✅ Double next-occurrence for repeating reminders (sync conflict)
Nudge owns recurrence: completing a repeating reminder spawns the next copy locally
(`NudgeStore.toggleComplete`). But `RemindersSync.writeToEK` now ALSO pushes
`recurrenceRules` to the Apple reminder. If a repeating item is completed in Apple
Reminders, Apple advances its own recurring copy AND Nudge spawns a duplicate next
occurrence on sync → duplicate reminders.
**Fix:** one owner. Stop pushing `recurrenceRules` in `writeToEK` (keep import-only
via `ekToRecurrence`/backfill), or strip the EK rule when mirroring a Nudge-recurring item.

### 2. ✅ Backup rotation churns itself useless
`NudgeStore.backupSnapshot` runs before EVERY sync — and sync is debounced ~1.2 s after
every single edit (`RemindersSync.scheduleEditSync`), plus every cloud `refresh()`.
The rotation keeps only 40 files, so a burst of editing can flush all useful history
in minutes — defeating the safety net added after the 2026-06-11 data-loss incident.
**Fix:** throttle — e.g. skip if last backup < 15 min ago; or keep hourly buckets +
a few daily ones. (`NudgeStore.swift`, `backupSnapshot` / call sites in `refresh()` and
`RemindersSync.reconcile`.)

### 3. ✅ `refresh()` can clobber local edits mid-debounce
`NudgeStore.persist()` debounces the cloud push 700 ms; `refresh()` (called on every
foreground) unconditionally applies the cloud blob over local state. Edit → background
→ foreground within the window and the UI reverts to stale cloud (the pending push then
re-uploads the edit, so cloud is fine, but local view flip-flops; with two devices it's
a real last-write-wins race).
**Fix:** skip `apply()` when a push is pending (`pushTask != nil`), or merge per-reminder
by `updatedAt` instead of wholesale replace.

### 4. ✅ Sync `Snapshot` ignores `url` + `recurrence` (url added; recurrence intentionally excluded — see item 1)
`RemindersSync.Snapshot` = title/dueCanon/notes/completed only. So editing ONLY the
repeat or link of a reminder in Nudge never marks it "changed" → never pushed to Apple;
Apple-side repeat/url edits also never flow after the one-time backfill.
**Fix:** add `url`/`recurrence` (canonical string) to `Snapshot`. ⚠️ Stored links decode
from disk — give new fields defaults (`var url: String = ""`) so old link files still
decode; otherwise links reset and re-import duplicates everything.

---

## P1 — Behaviour bugs

> **Status: all 5 fixed & deployed to Mac 2026-06-11 (iPhone locked — push manually).**

### 5. ✅ Date-only reminders are "Overdue" from midnight
A reminder with a due *date* but no time stores `startOfDay`. `isOverdue` and
`sections()` compare `d < now`, so it's overdue at 00:01 on its due day — all day.
Should be "Today" until the day ends.
**Fix:** when `hasTime != true`, treat due as end-of-day for overdue checks
(`NudgeStore.isOverdue`, `sections()` — the `day == today && d < now` branch).

### 6. ✅ Notification snooze gets cancelled by the next reschedule pass
The "Snooze 1 hour" notification action sets `snoozedUntil` and schedules a one-off
re-alert — but any later data change triggers `NotificationManager.reschedule()`, which
calls `removeAllPendingNotificationRequests()` and re-schedules **from `dueDate` only**.
The due date is in the past → no notification re-created → the snooze re-alert is lost.
**Fix:** in `reschedule()`, compute fire time as `max(dueDate-based fire, snoozedUntil)`.

### 7. ✅ Two different snooze semantics
Notification action snooze: only sets `snoozedUntil` (due stays old). Card context-menu
snooze (`NudgeStore.snooze`): rewrites `dueDate` AND `snoozedUntil`. Pick one model —
recommend the card behaviour everywhere (rewriting due keeps Apple sync + Timetable sane).

### 8. ✅ `dismissed` is vestigial and inconsistently filtered
Nothing ever sets `dismissed = true` (web triage *deletes* instead). Sync and
Notifications filter it; `open()`/`sections()`/list counts don't. If anything ever sets
it, items would ghost in lists but stop syncing/notifying.
**Fix:** either filter `dismissed` in `NudgeStore.open()` or remove the field entirely.

### 9. ✅ Dead code: `NaturalDate.swift`
The Home quick-add bar was removed, leaving the whole NL date parser unused (plus its
leftover `var c … _ = c` hack). Delete it, or (better) wire it into AddReminderView so
typing "gym tomorrow 7pm" in the title pre-fills the date.

---

## P2 — Polish / smaller issues

> **Status: 10–13 + 16 fixed & deployed to Mac 2026-06-11. (14 done, 15 verified above.)**
> Live cloud-polling sync added (web edits now appear within ~15s without force-quit).

### 10. ✅ Home "fit" math is stale
`dashboardTab` computes visible Today rows with hard-coded `fixedTop = 600/540`; the
layout has since gained/lost blocks (pinned section added, quick-add removed). Recompute
or measure properly. (`ContentView.swift`.)

### 11. ✅ Mac: app-lock blur on every focus loss
On Catalyst, `scenePhase == .inactive` fires whenever the window loses focus, so with
Face ID lock enabled the LockShield blur covers the app on every cmd-tab. Probably
desirable for privacy, but verify the `.active` → `hide()` path always wins; consider
only blurring on `.background` on macOS.

### 12. ✅ Swipe-to-delete has no undo
Given the recent data-loss scare, a 3–4 s "Deleted · Undo" toast after swipe-delete
would be cheap insurance. (`ReminderCardView.swipeGesture`.)

### 13. ✅ Model comment drift + copy
- `Models.swift` `source` comment says `"manual" | "studytrack" | "finance"` — missing
  `apple`/`auto`.
- Greeting "Early Morning" (others say "Good …") — intentional?
- `Theme.violet`/`violetGrad` legacy aliases for accent — rename or comment.
- `sections()` upcoming: `else if d <= weekEnd` and the following `else` both append to
  `upcoming` — collapse the dead branch.

### 14. ✅ Model fields with no iOS UI — DONE
Added an **Early reminder** picker (`remindBefore`) and a **Subtasks** editor to
`AddReminderView`; subtasks + early-reminder badges now render on the card; threaded
both through `NudgeStore.saveReminder`. (Part of the 2026-06-11 feature batch.)

### 15. ✅ Web ⇄ iOS parity for `pinned` — VERIFIED SAFE
`updateReminder` uses `Object.assign(r, patch)`, so web edits **preserve** `pinned`
(and url/location/lat/lng/section) added on iOS — no data loss. Web subtasks +
`remindBefore` already existed. ⏭ *Remaining (optional):* a visible pin toggle +
pinned section on the web UI, and porting Smart Collections / time-presets to web.

### New 2026-06-11 feature batch (beyond original review)
- **Early reminders** (iOS UI + notification "⏰ Heads-up" display).
- **Subtasks** (iOS editor + card progress badge; web already had them).
- **Buy → Shopping rule**: a new "buy …" reminder auto-files to the Shopping list at
  a fixed 9 AM, bumped to the next free slot if 9 AM is taken; notification shows 🛒.
  Mirrored on **both** iOS (`AddReminderView.applyBuyRule`) and web (`saveQA`).

### 16. ✅ No restore UI for backups
Backups now exist (Documents/backups, last-40) and Settings shows "Last backup", but
there's no in-app restore. Add a "Restore from backup…" picker (read-only list → confirm).

### 17. Repo hygiene
- The entire `ios/` app + `reinstall_nudge.sh` + helper scripts are **untracked in git**
  (only the web app is pushed). One disk failure loses the native app.
- Zero tests. Highest-value unit targets: sync reconcile (link loss / stale-overwrite
  regression), `sections()` bucketing incl. date-only items, recurrence `nextOccurrence`.

---

## Context for whoever fixes this
- Sync incident 2026-06-11: stale Apple copies overwrote Nudge edits; merge has been
  hardened (title-fallback relink, Apple-wins-only-if-strictly-newer, pre-sync backups).
  Items 1–4 above finish that hardening properly.
- Backups land in the app's `Documents/backups/` (rotating 40). A one-off pre-incident
  snapshot lives at `~/nudge_recovery/cache_sim_jun10.json` — don't touch it.

## Build, verify, deploy
- Compile-check (fast, no devices needed):
  `xcodebuild -project ios/Nudge/Nudge.xcodeproj -scheme Nudge -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
- Deploy after EVERY change set: `./reinstall_nudge.sh` — installs to iPhone
  (device must be **unlocked, screen on**; if preflight fails, deploy Mac only by
  killing `Nudge` and `open`-ing the Debug-maccatalyst app from DerivedData, then
  retry the script when the phone is unlocked) **and** relaunches the Mac app.
- Xcode 16 synchronized folders: new .swift files in `ios/Nudge/Nudge/` are picked up
  automatically — no pbxproj editing.
- The shared data blob is LIVE personal data (Supabase, no history). Don't run
  destructive experiments against it; items 1–4 specifically protect it.
- No test target exists yet. If you add one (item 17), keep it pure-Swift units
  (date math, merge logic) so it runs without a device.
