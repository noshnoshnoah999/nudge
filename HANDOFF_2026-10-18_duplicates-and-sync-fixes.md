# Handoff — 2026-10-18: duplicate reminders, reverting edits/links, completion lag

Code commits: `708b056` (duplicate fixes) and `a498386` (audit fixes + features), both local
and unbuilt at time of writing. Build/push prompt:
`CLAUDE_CODE_PROMPT_2026-10-18_duplicates-fix.md`.

## What Noah reported
1. Reminders duplicated 2–5×.
2. After a change on one device, the day's total on the OTHER device goes up (both directions).
3. "Send 1st Revolut Request": the title text appears twice inside one reminder; he deleted the
   extra text on the iPhone and it came back.
4. Removed a link from a recurring reminder, chose "future events", and the link keeps coming back.
5. Ticking several reminders in a row: slight freeze / lag, mainly iPhone, any screen.

Apple Reminders sync was ON on both iPhone and Mac.

## Root causes (from reading code — NOT verified against real data; reading the Mac's
## Application Support/Nudge folder was not permitted this session)

**A. Apple Reminders mirror on two devices (bugs 1, 2, likely 3).** `RemindersSync` keeps its
Nudge↔Apple links in a LOCAL file (`nudge_sync_links.json`). Each device therefore created its own
Apple twin of every reminder, and saw the other device's twin as an unknown Apple item. Reconcile
step 3 imports any unknown Apple item whose title+due-to-minute doesn't match a live Nudge reminder
as a NEW reminder with a NEW id. Edits/completions/carry-over/bulk moves reach the other device via
Supabase in seconds but the Apple copies lag in iCloud, so the match fails and a stale copy is
imported, uploaded, and then gets its own twins — compounding to 3–5×. Imported items land in the
"Reminders" list (`newNudgeReminder`), consistent with the card above Revolut in Noah's screenshot.

**B. Links (bug 4).** `writeToEK` never cleared Apple's link ("never clear Apple's"), so the next
reconcile saw Apple still holding it, treated that as an Apple-side change, and `writeToNudge` /
`backfillFromApple` copied it back. The "future events" save itself was correct.

**C. Non-idempotent completions (bug 1, smaller sources).**
- Card double tap: flair commits 0.76 s after the tap with no guard → complete then un-complete;
  for a repeat the spawned next occurrence stayed.
- Untick a repeat: spawned next stayed; re-tick spawned another.
- Widget: completed rows that were already completed (stale widget) → second successor.
- Notification "Complete" action toggled, so it could UN-complete.
- Every spawn site used a random id.

**D. Push race (bug 3, contributory).** `pushAll` marked `meta.sig` as pushed AFTER the network
await; an edit persisted during the await was marked pushed without being uploaded, so the other
device never got it and later overwrote it.

**E. Lag (bug 5) — not measured.** Each tick ran, on the main thread: `refreshSignatures` (JSON +
SHA-256 of every reminder) + full cache encode + disk write; again 0.7 s later in the push; and
1.2 s later a full Apple Reminders reconcile (DateFormatter created per reminder, several times).

**Bug 3's doubling itself: cause unknown.** No code in Nudge concatenates title text. Candidates
(unverified): the multi-line title TextField input, or Apple Reminders/iCloud handling of a
multi-line title. If it recurs with Apple sync off, it's the text input.

## What changed (708b056)
- `RemindersSync.isAvailable = false`: sync can't run, enabled flag persisted false, Settings
  section hidden. Code kept for reversibility. Links fix applied too (clears Apple's link; no
  link backfill).
- `RecurrenceEngine.successorId(of:)` — deterministic successor id (SHA-256 of parent id). Used by
  `toggleComplete`, `saveReminderThisOccurrenceOnly`, RemindersSync's Apple-completion path, and the
  widget intent.
- `toggleComplete`: spawns the successor only if absent (clearing any tombstone so re-tick revives
  it); untick tombstones the successor if it is still untouched (`!completed && updatedAt ==
  createdAt` — both stamped from one `now`). Noah asked for exactly this.
- Widget: skip rows already completed; check successor state (`live` → leave it, `absent/deleted`
  → upsert with explicit `deleted_at: null`, check failed → don't complete).
- `ReminderCardView`: ignore a repeat tap within 0.8 s; delayed flair action completes only if
  still open.
- `Notifications`: Complete action returns if already completed.
- `CloudSync`: `signaturesBeingPushed` + global `markPushed(_:meta:)`; `SyncMeta.memo` (in-memory,
  excluded via CodingKeys) lets `refreshSignatures` skip unchanged items by `hashValue`.
- `NudgeStore.writeCache`: atomic write on a serial background queue.
- `saveReminder`: keyed on `targetId`, so a double-tapped Save on a new reminder can't insert twice.
- Tests: run.sh includes RecurrenceEngine; new cases 10–12. Changelog 2.31.

## Not done / Noah's to-do after install
1. Install on BOTH devices (old build anywhere = mirror still running).
2. Clean existing duplicates: iPhone → Settings → Maintenance → Remove duplicates (review list,
   confirm). Only catches identical title + time; stale-text copies (often in the "Reminders" list)
   must be deleted by hand.
3. Optional: delete the leftover "Nudge" list in the Apple Reminders app — nothing reads it now.
4. Older successors spawned before this build have random ids, so unticking THOSE won't remove
   their next occurrence. Only new completions behave the new way.

## Test checklist
- Settings: Apple Reminders section gone.
- Tick a repeating reminder → exactly one next. Untick → next disappears. Re-tick → back, one copy.
- Double-tap a tick circle fast → completes once.
- Widget: complete a repeating reminder → one next, on both devices.
- Remove a link from a recurring reminder (future events) → still gone after a minute and on Mac.
- Edit on iPhone, open Mac → count unchanged (and vice versa).
- Tick 5 in a row → smoother than before.

---

# Part 2 — whole-app audit (2026-10-19, commit `a498386`)

Noah asked for a full bug check after the duplicate fixes, then said "fix all", plus two features.

## Fixed
- **H1 — server kept the LAST upload, not the newest.** Blind `merge-duplicates` upserts let a
  stale upload (offline edit, slow request) overwrite a newer row; the newer device then skipped
  the older incoming row forever → permanent divergence. Client: `mergeRows` re-dirties our copy
  when the server holds an older one (`healedCount`), and `refresh()` schedules the push.
  Server: `supabase/d1/06_reject_older_writes.sql` — **Noah must run it in the Supabase SQL
  editor** (trigger skips strictly older updates on reminders/lists/smart_lists/settings; also
  revokes API execute on `purge_nudge_tombstones()` if that function exists).
- **H2 — fresh install could get only part of the data.** `CloudAPI.pull` asked for every row in
  one unordered request; Supabase caps responses (1000 by default) and tombstones accumulate.
  Now paged by `id` until an empty page.
- **M1** snoozing a repeating reminder shifted the series → only `snoozedUntil` now.
- **M2** Quick Catch Save / Scan "Add N" double tap → duplicates → one save per sheet.
- **M3** Smart Reschedule + Bulk Move moved repeating reminders' series → they're excluded
  (Noah: "keep its set time, no matter what"); bulk-move sheet shows how many were skipped.
- **L1** birthday notifications wiped from Notification Centre by `clearStaleDelivered`.
- **L3** LocationMonitor rebuilt every geofence on every persist → only when the set changes.
- **L6** deleted `config.js`, `fix_strange_times.py`, `make_shortcut.py`,
  `Nudge Morning Digest.shortcut` (retired; anon keys only, still in git history — harmless
  under RLS).

## Features
- **AI move-over, ask-first** (replaces the automatic 23:50 carry-over; also fixes L2, the
  per-device double runs). First device opened each calendar day claims the day in the synced
  settings row (`moveOverOffer` = day/device/state) after a successful pull, then re-pulls to
  confirm; only the claimer shows "N reminders left from yesterday — Run AI move-over / Skip
  today". Other device: nothing that day, even if ignored (Noah's choice). Needs an API key;
  offline → no claim. Two devices opened within ~1 s can both claim (settings row is
  last-write-wins). BG task no longer runs it. Result still logged in CarryOverLog ("AI
  move-over done" banner).
- **Birthday banner** on Home (`BirthdayBanner.swift`): on the day "Say happy birthday to X!",
  and 1–3 days before a heads-up; ✕ hides it for that day (per device).

## Not fixed (info only)
- L4: iOS schedules at most ~60 pending alerts; long absences can miss later ones.
- L5: Siri intents / BG task / notification fallback create extra NudgeStore instances in the
  same process; self-heals on next pull.
- Nightly AI grouping (`maybeRunDailyGrouping`) still auto-runs per device if its toggle is on —
  same double-run shape as the old carry-over. Not raised by Noah; flag if he wants it ask-first too.

## Noah's to-do (in order)
1. Hand Claude Code the prompt; install on BOTH devices.
2. Supabase dashboard → SQL editor → paste and run `supabase/d1/06_reject_older_writes.sql`.
   The last two SELECTs should show 4 trigger rows and the row/tombstone counts.
3. iPhone → Settings → Maintenance → Remove duplicates (review, confirm).
4. Optional: delete the leftover "Nudge" list in Apple Reminders.

## Extra test checklist
- Snooze "FaceTime Dad" an hour → next week still 16:15.
- Select a mix incl. a repeating reminder → Bulk Move → note says 1 left out; it doesn't move.
- Smart Reschedule never lists repeating reminders.
- Double-tap Quick Catch Save → one reminder.
- First open tomorrow morning on one device → move-over banner; open the other → no banner.
- A birthday within 3 days → Home banner; ✕ hides it until tomorrow.
