# Handoff — 2026-10-18: duplicate reminders, reverting edits/links, completion lag

Code commit: `708b056` (local, unbuilt at time of writing). Build/push prompt:
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
