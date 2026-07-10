# Nudge — Full Bug Audit Handoff (2026-07-09)

Audit scope: full sweep — web app (`index.html`, `sw.js`, `manifest.json`), iOS/macOS app (57 Swift files), cross-platform sync consistency. Static review only (no Xcode build available in the audit environment). Web fixes were applied and verified with a Node test harness; Swift issues are documented below for Opus to fix in Claude Code where they can be compiled and tested.

---

## Part 1 — FIXED in this session (web, `index.html` only)

All six fixes bring the web app into line with behaviour iOS already implements correctly. No Swift changes were needed for these. JS syntax-checked (`node --check`) and logic-tested.

### F1. Recurring completion lost recurrence settings (MAJOR)
`completeReminder()` spawned the next occurrence via `addReminder()`, which hard-reset `interval` to 1 (every-2-weeks became weekly), and dropped `until`, `tz`, `remindBefores`, `subtasks`, and every iOS-only field (url, location, pinned, group, prep links). Now spawns a full copy of the reminder with per-occurrence overrides — mirrors iOS `toggleComplete`.

### F2. "Save for This Event Only" leaked edits into the series (MAJOR)
`applyRecurThisOnly()` snapshotted only the recurrence, then read `orig.title/notes/priority/listId/…` AFTER `updateReminder()` had mutated the object. Result: the "unchanged" continuing series silently inherited the edit, and the hand-built continuation dropped iOS-only fields. Now snapshots the whole reminder before mutation — mirrors iOS `saveReminderThisOccurrenceOnly`.

### F3. Undo-after-complete corrupted state (MAJOR)
Undo called `completeReminder()` again (a toggle). For recurring reminders this left the spawned next occurrence behind as a duplicate. For routines it rolled the schedule forward a SECOND time (routines treat any tick as "did it"). Undo now restores a snapshot of the reminders array taken before the completion (card view and board view).

### F4. Date-only reminders showed overdue from 00:01 (divergence from iOS)
Web `isOverdue()` used `dueDate < now`; iOS treats a no-time reminder as overdue only after its whole day passes. Web now matches, and `groupReminders()` uses `isOverdue()` for bucketing (same rule as iOS `sections()`).

### F5. Triage "Today 9am" could reschedule into the past
`snoozeReminder(id, 0)` after 9am set a due time earlier today → item stayed overdue and re-entered triage. Past results now roll to the top of the next hour. Also stamps `updatedAt` (it didn't, which skewed Apple-sync conflict resolution).

### F6. PWA shortcut actions were dead + `Notification` crash guard
`manifest.json` declares `?action=add` / `?action=triage` app-icon shortcuts but `init()` never read them — now handled. `renderSettings()` used `Notification?.permission`, which throws ReferenceError where `Notification` is undeclared (non-secure contexts) — now `typeof`-guarded.

---

## Part 2 — FOR OPUS: Swift bugs (need Xcode build + device test)

### S1. Completing a recurring reminder in Apple Reminders kills the series (HIGH)
`RemindersSync.swift` → `reconcile()` step 1: when Apple's copy is newer, `writeToNudge()` sets `completed = true` on the Nudge reminder. Routines are special-cased (`advanceRoutine`), but a plain **recurring** reminder just completes — nothing spawns the next occurrence (that only happens in `toggleComplete`, which sync never calls). `writeToEK` deliberately flattens recurrence on the Apple side ("Nudge is the single owner of recurrence"), so Apple won't advance it either. The series silently dies.

**Fix:** in the `eChanged && eTime > nTime` branch of `reconcile()`, after `writeToNudge(&rr, from: ek)`, add: if `rr.completed == true`, `rr.recurrence` is set (freq != "none"), and the previous state was incomplete, spawn the next occurrence exactly like `toggleComplete` does (full copy, new id, `nextOccurrence(after:rec:)`, insert at 0, `nudgeChanged = true`). Keep the completed one as history.

### S2. Transient empty EventKit fetch could mass-delete Nudge data (HIGH, data-loss class)
`reconcile()` case `(idx?, nil)`: a linked reminder whose Apple twin is missing gets deleted from Nudge (after re-link attempts fail). If `fetchReminders` returns an empty/partial list transiently (iCloud hiccup, permission blip — the completion handler maps `nil → []`), EVERY linked reminder is treated as Apple-deleted and removed in one pass. The pre-merge `backupSnapshot("sync")` is 10-minute throttled, so the safety snapshot may not even be taken. This matches the class of incident behind `nudge_recovery/`.

**Fix (two parts):**
1. In `reconcile()`, before processing links: `if eks.isEmpty && !links.isEmpty { status = .error("Apple returned no reminders — skipped to protect data"); return }`. A user legitimately emptying the Apple list is rarer and still recoverable via backups; silently nuking the store is not.
2. If `nudgeIdsToDelete.count` exceeds a small threshold (e.g. 5 or >30% of links), force a backup (`backupSnapshot("sync-massdelete", force: true)`) before applying, or require confirmation.

### S3. Early alerts stay suppressed after a snooze expires (LOW)
`Notifications.swift` `reschedule()`: early alerts are skipped whenever `parseDate(r.snoozedUntil) != nil` — but `snoozedUntil` stays set after it passes (only complete/edit clears it). Should skip only when the snooze is still in the future.

---

## Part 3 — FOR OPUS: cross-platform / design decisions (discuss with Noah first)

### D1. Whole-blob last-write-wins sync (architectural) — ✅ FIXED 2026-07-10
Shipped as per-item rows + tombstones. See `D1_SYNC_DESIGN_per-reminder-merge.md` **§11 (as built)** and
`supabase/d1/`. The description below is the original diagnosis, kept for context.

Both platforms POST the entire `nudge_data` blob. iOS at least guards pulls with `hasPendingPush`; web pulls once at load and unconditionally overwrites localStorage. Offline web edits die on next load if another device pushed meanwhile; two devices editing near-simultaneously clobber each other item-by-item. Proper fix is a per-reminder merge keyed on `updatedAt` (both models already carry it). Non-trivial; needs a design pass.

### D2. Secrets in the client (SECURITY — ACTION REQUIRED, Noah has approved fixing this)
`index.html` ships the Supabase anon key AND the secret `user_key` row keys (Nudge + Finance projects) in plain text. Anyone who can view the page source can read AND write all reminder + finance data (writes use the same anon key + user_key). The same keys are compiled into the iOS app and the widget extension (`NudgeStore.swift`, `WidgetData.swift`) — extractable from the binary too.

**Noah's instruction: get these secrets out of sight. Be honest about the limits — a client-side app cannot truly hide a credential it uses; the fix is to make the credential worthless to an attacker, not invisible.** Do it in this order:

1. **Proper fix — Supabase Auth + Row Level Security.** Create a real Supabase user for Noah; enable RLS on `nudge_data` (and the finance project's table) with policies keyed to `auth.uid()`, replacing the guess-the-user_key model. The anon key then becomes safe to ship (that is its designed purpose) because it grants nothing without a signed-in session. Web: add a small login (email magic-link is fine, persist the session). iOS/widgets: store the session/refresh token in the Keychain, not UserDefaults. This is the only option that actually secures the data.
2. **Interim hygiene (do immediately, even before 1):**
   - Move the config out of `index.html` into an untracked `config.js` (`.gitignore` it, ship a `config.example.js`), so the secrets stop living in git history and diffs. NOTE: this protects the repo, NOT a hosted page — the browser still downloads it.
   - Rotate the `user_key` values once the above lands (the current ones must be treated as burned — they are in git history).
   - Confirm the repo remote is private and stays private; if it was ever public, rotate keys regardless.
3. **Not acceptable as a fix:** base64/string-splitting/JS obfuscation of the keys. Do not do this and call it done.

Until 1 is done, the web app must not be hosted anywhere public.

### D3. `dismissed` never set, web ignores it
No iOS code sets `dismissed = true` today, but iOS filters on it everywhere and web doesn't filter at all (`visibleReminders`, `allOverdue`, counts). The moment anything sets it, web diverges. Cheap web patch; do it whenever `dismissed` gains a writer.

### D4. Web routine tick leaves no history entry
iOS `routineDidIt` inserts a completed snapshot (shows in Completed, counts for "Done today") and clears `completedAt` on the live routine. Web rolls the routine forward and stamps `completedAt` on the still-open reminder — no history entry, and a nonstandard `completed:false + completedAt` state. Harmless for purge (it checks `completed`), but "Done today" counts differ between platforms.

### D5. Finance/StudyTrack visibility differs
iOS hides `source == finance/studytrack` reminders (`hiddenSource`, round-tripped untouched); web displays them. May be intentional (web created them) — confirm with Noah, document either way.

### D6. Minor web items
`sw.js` cache name `nudge-v1` never bumped (icons cached forever; HTML is network-first so app updates land). Escape key hides recur-scope overlays without clearing `ui.pendingRecurEdit`/`ui.pendingDelete` (stale but harmless — overwritten on next open). `dedupeReminders()` key concatenates fields with no separator (theoretical boundary collisions). Web snooze is days@9am vs iOS minutes-based (compatible, just inconsistent UX).

---

## Verification done
- `node --check` on the extracted script: clean.
- Node harness over the changed functions (verbatim extraction): biweekly spawn keeps interval 2 + url/pinned/alerts/deep-copied subtasks; This-Event-Only keeps original title/notes/priority/list/location/group on the continuation and applies edits only to the detached one; date-only today ≠ overdue, date-only yesterday = overdue, timed past = overdue.
- iOS lock/grace-period invariant re-checked while auditing: cancelled Face ID still never bypasses (memory note holds).

## Files touched
- `index.html` — 6 fixes (+58/−20). Nothing else modified.
