# D1 — Per-Item Sync Design (kill whole-blob last-write-wins)

**Status:** ✅ **SHIPPED 2026-07-10.** Migrated, deployed to iPhone + Mac, two-device delete test passed.
**⚠️ Read §11 FIRST.** Sections 1–10 below are the *original design* and are **wrong in five places**.
§11 records what was actually built, and why. Where they disagree, §11 is correct.
**Author:** Cowork session, 2026-07-10.
**Decision owner:** Noah.
**Applies to:** iOS + Mac Catalyst apps (the web app is retired). Supabase project holding `nudge_data`.

---

## 0. TL;DR

Nudge stores all of your data as **one JSON blob in a single Supabase row**. Every save overwrites
the whole blob, so whichever device saves last wins — and a delete is just "my blob no longer
contains X", which any device still holding X will silently undo on its next save.

This document specifies moving to **one row per item** (per reminder, per list, per smart list) with
a `updated_at` timestamp and a `deleted_at` **tombstone** on every row, plus a single per-user
`settings` row. Sync becomes "pull rows changed since I last synced; push my changed rows; merge
per item by newest `updated_at`; a delete beats a concurrent edit." This makes the clobber bug
**structurally impossible**, not merely rarer.

Locked decisions (Noah, 2026-07-10):
1. **Architecture:** one row per reminder / list / smart list; `settings` as one per-user row.
2. **Tombstones:** soft-delete with `deleted_at`, purged after **90 days**.
3. **Conflict rule:** newer `updated_at` wins per item; **a delete always beats a concurrent edit.**

---

## 1. The bug, precisely (why your delete came back)

Reproduction you hit: deleted a reminder on the Mac; it stayed on the iPhone; then reappeared on the
Mac.

Mechanism, traced through `NudgeStore.swift`:

1. **Mac delete.** `deleteReminder(_:)` removes it from `reminders`, calls `persist()`. `persist()`
   sets `hasPendingPush = true` and schedules `push()` after a **700 ms debounce**.
2. **Mac push.** `push()` uploads the Mac's *entire* blob (reminder absent) via `pushCloud()` — an
   upsert on `user_id`. On success its `defer` sets `hasPendingPush = false`. Cloud is now clean.
3. **iPhone never saw the delete.** Its in-memory `reminders` still contains the reminder. The delete
   was never communicated to it as a *delete* — there is no such concept in the blob model.
4. **iPhone pushes its blob.** Any trigger — an edit, a completion, the EventKit mirror firing
   `.nudgeDataChanged`, a routine roll-forward — calls `persist()` → `push()`, which uploads the
   iPhone's full blob **including the reminder you deleted.** Cloud now has it back.
5. **Mac background poll.** `refresh()` → `fetchCloud()` runs (the 15 s poll). It sees a cloud blob
   that differs from local; `hasPendingPush` is `false`; so it calls `apply(blob)`. The deleted
   reminder **reappears on the Mac's screen.**

The root cause is not a timing bug that a better guard would fix. It is that **a delete has no
representation** in the data model. Deletes can never win against a device that still holds the item.
`hasPendingPush` only protects *your own un-pushed edits from an incoming refresh* — it does nothing
about another device re-adding what you removed. Tombstones are therefore not optional; they are the
fix.

Same reasoning applies to lists, smart lists, and settings — all four ride in the one blob and clobber
identically. That is why the scope is all four (Noah's decision).

---

## 2. Current model (as built)

From `NudgeStore.swift` and `Models.swift`:

```
struct NudgeData: Codable {
    var reminders: [Reminder]
    var lists: [ReminderList]
    var smartLists: [SmartList]?
    var settings: [String: JSONValue]?
}
```

- `Reminder` is `Codable, Identifiable, Hashable` with a stable `var id: String`, `var createdAt: String?`,
  and **`var updatedAt: String?`** ("last local edit; used as tiebreak vs Apple's lastModifiedDate").
  It also has `var dismissed: Bool?`.
- Cloud storage: table `nudge_data`, one row per user, column `data` holds the whole `NudgeData` JSON.
  RLS is live: `auth.uid() = user_id`. Upsert is `POST …/nudge_data?on_conflict=user_id` with
  `Prefer: resolution=merge-duplicates`.
- Reads: `GET …/nudge_data?select=data` → `[Row]`, `Row { data: NudgeData }`, take `rows.first?.data`.
- **`hasPendingPush`**: set true in `persist()`/`persistNow()`, cleared in `push()`'s `defer`. In
  `fetchCloud()`, when it's true an incoming blob is *not* applied (protects un-pushed local edits).
- **`backupSnapshot("cloud")`**: called in `fetchCloud()` right before `apply(blob)` overwrites local,
  so a bad sync can be rolled back from the rotating on-disk backups (60 kept, throttled 1/10 min).
- Hidden-source reminders (`source == "studytrack"` / `"finance"`) are filtered out of the UI but kept
  in `hiddenSource` and re-attached via `fullReminders()` so a push round-trips them untouched.
  **The new model must preserve this** — see §7.

Every mutation path already stamps `updatedAt = iso(Date())` (verified: `toggleComplete`,
`deleteReminder` path, `snooze`, `reschedule`, `saveReminder`, `advanceRoutine`, carry-over, grouping,
etc.). This is what makes per-item merge viable with no new bookkeeping — **except** deletes, which
today just drop the element and therefore leave no timestamped trace. That is the gap tombstones fill.

---

## 3. Target model

### 3.1 Tables

Four tables, all under the same RLS pattern (`auth.uid() = user_id`).

**`reminders`**
| column       | type          | notes                                                        |
|--------------|---------------|--------------------------------------------------------------|
| `id`         | text          | the reminder's existing stable id (e.g. `r1a2b3c4…`). PK part.|
| `user_id`    | uuid          | default `auth.uid()`; PK part. RLS key.                      |
| `data`       | jsonb         | the full `Reminder` JSON (all fields, unchanged).            |
| `updated_at` | timestamptz   | mirror of `Reminder.updatedAt`; the merge key + index.       |
| `deleted_at` | timestamptz   | NULL = live; non-NULL = tombstone.                           |

Primary key `(user_id, id)`. Index on `(user_id, updated_at)` for "changed since" pulls.

**`lists`** and **`smart_lists`**: identical shape (`id`, `user_id`, `data`, `updated_at`, `deleted_at`).

> **Model change required:** `ReminderList` and `SmartList` must each carry an `updatedAt` (and be
> stamped on every edit) for the same merge to work. `Reminder` already has it. Audit their writers
> (list create/rename/reorder, smart-list edit) and add `updatedAt = iso(Date())` on each, mirroring
> how reminders are stamped. This is the one model addition outside reminders. (Flagged as a
> prerequisite task, §9.)

**`settings`**: one row per user — `user_id` (PK), `data` jsonb, `updated_at`. No `deleted_at`
(settings is a single bag with no per-item identity; it's merged whole on `updated_at`, last-writer-
wins, which is acceptable for a preferences blob).

### 3.2 Why timestamptz mirrors the JSON `updatedAt`

Keeping `updated_at` as a real column (not only inside `data`) lets the *server* filter
(`updated_at=gt.<cursor>`) so a pull transfers only changed rows. The value is written by the client
from `Reminder.updatedAt`; the client is the source of truth for edit time (offline edits get their
real local time). We do **not** use a DB-side `now()` default for `updated_at`, because an offline
edit must keep the timestamp of when it was actually made, not when it later reached the server.

### 3.3 Clock-skew note

Merge-by-timestamp trusts device clocks. iPhone and Mac clocks are NTP-synced and this is a single
user, so skew is negligible. Documented as an accepted limitation. If it ever bites, the mitigation is
a server-assigned monotonic sequence, but that's out of scope here.

---

## 4. Sync algorithm

Per client, keep a **sync cursor**: the `updated_at` high-water mark of the last successful pull
(stored locally, e.g. in the cache file or UserDefaults). Start it at epoch 0 on a fresh install.

### 4.1 Pull (`refresh()` rewrite)

1. Guard exactly as today: signed out → `setSync("Local")`, return. An unauthenticated RLS read
   returns `[]`; that must never reach a merge (see §6).
2. For each of `reminders`, `lists`, `smart_lists`: `GET …?select=id,data,updated_at,deleted_at&updated_at=gt.<cursor>`
   — only rows changed since the cursor (tombstones included). Fetch `settings` whole.
3. **Merge each incoming row into local (§5).** Do *not* wholesale `apply()` a blob any more.
4. Advance the cursor to the max `updated_at` seen across the pulled rows (only on overall success).
5. Persist the merged local state to the on-disk cache; reload widgets; `setSync("Synced")`.
6. `syncPrepReminders()` afterwards, as today.

### 4.2 Push (`push()` rewrite)

The client tracks a **dirty set**: ids of items changed locally since their last successful push.
(Cheapest implementation: a `Set<String>` per table in the store, added to wherever `updatedAt` is
stamped, cleared on push success. See §7 on `hasPendingPush`.)

1. Guard as today: signed out → keep local, `setSync("Local")`, return.
2. For each dirty reminder/list/smart-list: **upsert one row** — `id`, `data`, `updated_at`, and
   `deleted_at` (NULL for live items, a timestamp for deletes). Upsert on `(user_id, id)`.
   A batch upsert (array body) is fine and preferred — one request per table, not one per item.
3. If `settings` is dirty: upsert the single settings row.
4. On success clear the dirty set. Keep the same single-401-retry-after-refresh pattern already in
   `push()`.
5. Check HTTP status (the existing fix — `URLSession` doesn't throw on 4xx). Only `2xx` → `"Synced"`.

Deletes are pushed as an **upsert that sets `deleted_at`**, not a `DELETE`. The row (a tombstone)
stays so other devices learn of the delete on their next pull.

---

## 5. Merge rules (the heart of it)

For an incoming item `I` (id = k) vs local item `L` (same id), and vice-versa:

**Reminders / lists / smart lists — per item by id:**

| Situation                                             | Result                                                        |
|-------------------------------------------------------|---------------------------------------------------------------|
| k exists cloud-only (not local)                       | If `I.deleted_at == nil` → insert `I` locally. If tombstoned → ensure absent locally (and keep the tombstone knowledge — see below). |
| k exists local-only (not in this pull)                | Leave it. It'll be pushed when dirty. (A pull is a delta; absence ≠ deletion.) |
| k in both, **neither** deleted                        | Keep the one with the newer `updated_at`. Equal → keep local (no-op; avoids churn). |
| k in both, **I deleted**, L live                      | **Delete wins:** remove `L` locally, retain tombstone. Applies even if `L.updated_at` is *newer* — delete beats concurrent edit (locked decision). |
| k in both, **L deleted** (local tombstone), I live    | **Delete wins:** local delete stands; the delete will propagate on next push. Do not resurrect. |
| k in both, both deleted                               | No-op; keep the earlier `deleted_at` (or either — cosmetic). |

**"Delete beats edit regardless of timestamp"** is the specific rule that fixes your reproduction:
even though the iPhone's live copy might carry a newer `updated_at` (from some unrelated edit), the
Mac's tombstone still wins and the reminder does not come back.

**Local tombstone tracking.** When a delete happens locally, the client cannot merely drop the item
from the in-memory array (that's today's bug). It must record a tombstone (id + `deleted_at`) so that
(a) it can be pushed, and (b) a pull carrying the still-live copy from another device doesn't
resurrect it. Two viable implementations:

- **Keep tombstoned reminders in `reminders` with a `deleted: true` + `deletedAt` field**, filtered
  out of every UI query (the app already filters on `completed`/`dismissed`, so add `deletedAt == nil`
  to `open()` and the section builders). Simplest; reuses the existing array.
- **A separate local `tombstones: [String: Date]` map.** Cleaner separation, but every merge/push has
  to consult it. More moving parts.

Recommendation: the **`deletedAt` field on `Reminder`** approach — it mirrors the DB row exactly, one
code path, and the app's existing "filter on a nullable flag" pattern already exists for `dismissed`.

**Settings** (whole-row): keep the copy with newer `updated_at`. Last-writer-wins on the whole
settings bag is acceptable — it's small, low-churn, and rarely edited on two devices at once.

---

## 6. Interaction with the existing safety machinery

### 6.1 `hasPendingPush`

Today it's a single boolean meaning "I have un-pushed local edits; don't let a refresh overwrite
everything." Under per-item merge its job is largely **replaced by the merge itself**: a pull no longer
overwrites local wholesale, so an un-pushed local edit with a newer `updated_at` naturally wins the
merge and is never lost.

- Replace the single boolean with the **dirty set** (§4.2). An item in the dirty set has un-pushed
  local changes; the merge already protects it (newer `updated_at` wins, and a local tombstone wins).
- The one residual race: a pull could complete and advance the cursor *between* a local edit and its
  push, but since the merge is per-item and timestamp-ordered, the local edit still wins on the next
  comparison. No blanket "skip the whole refresh" guard is needed.
- **Keep a lightweight guard only for the settings whole-row** (no per-item identity there): if
  settings is dirty locally, don't let an older incoming settings row overwrite it — the `updated_at`
  comparison already handles this, so in practice the dirty set suffices here too.

Net: `hasPendingPush` (the boolean) is **removed**; the dirty set subsumes it.

### 6.2 `backupSnapshot("cloud")` in `fetchCloud()`

Today it snapshots local *before* a cloud blob replaces it — insurance against a bad wholesale
overwrite. Under per-item merge there is **no wholesale overwrite**, so the original trigger is gone.
But the safety value is real, especially during and just after migration. Recommendation:

- **Keep a snapshot, but move and re-scope it.** Take `backupSnapshot("cloud-merge")` **once per pull
  that actually changes local state**, before applying the merged result — not on every poll. The
  existing 10-minute throttle already prevents churn; keep it.
- Rationale: if a merge rule bug ever deletes or mangles items, you still have the rotating on-disk
  backups (60 kept) to restore from via the existing Settings restore screen. This is cheap insurance
  and the S2 history argues for keeping it.
- Do **not** remove the backup system. It's independent of the sync model and is your last line of
  defense.

### 6.3 EventKit mirror / `.nudgeDataChanged`

Unchanged in intent. The mirror still fires on local changes. Ensure the sync engine's own
write-backs (merge results applied to local) continue to pass `notify: false` where they already do,
to avoid a feedback loop. A merged-in delete from the cloud should clear notifications for that id
(mirror `deleteReminder`'s `clearNotifications(for:)` call) — add that to the merge's delete branch.

---

## 7. Preserving existing behaviors

- **Hidden-source reminders** (`studytrack` / `finance`): today they're kept in `hiddenSource` and
  re-attached via `fullReminders()` so a whole-blob push round-trips them. Under per-row sync each is
  just its own row like any other reminder; **do not filter them out of push** — they must be upserted
  as their own rows or they'd be seen as "deleted from this device" (though note: absence in a pull is
  *not* a delete under §5, and this device never tombstones them, so they're safe — but they must
  still be pushed if this device edits them). Keep the UI filter; drop the special push re-attachment.
  Verify no path tombstones a hidden-source row.
- **Undo delete** (`recentlyDeleted` / `undoDelete()`): still works locally. An undo within the window
  re-inserts the reminder and stamps a fresh `updatedAt`; since that's newer than the tombstone's
  `deleted_at`, the un-delete propagates correctly. **Confirm the undo clears the local tombstone /
  `deletedAt` field** so the item is live again.
- **Purge old completed** (`purgeOldCompleted`): these become real deletes → must write tombstones
  now, not silent drops. Same for the completed-history auto-clear.
- **Routine roll-forward, recurrence spawn, "this occurrence only"**: these create new reminders with
  new ids and stamp `updatedAt` — they push as new rows, no special handling.

---

## 8. Migration (moving the 195 reminders without losing them)

**Non-negotiable: full backup first, verification after. The app's data-loss history (the
`nudge_recovery` incident, the S2 mass-delete) means this runs with belt and braces.**

### 8.1 Preconditions
- Both apps signed in and confirmed syncing on the **old** blob model first (per the memory note,
  Mac sync is signed-in-but-unverified — verify before migrating).
- A fresh manual backup taken (the app's Settings → backup, plus the existing
  `~/Nudge_backups/` snapshot), copied **off-device**.

### 8.2 Steps
1. **Create the four new tables** with RLS policies (`auth.uid() = user_id`) — reminders, lists,
   smart_lists, settings. Do **not** touch `nudge_data` yet.
2. **Backfill from the existing blob.** A one-off server-side (SQL) or one-device script reads the
   single `nudge_data` row and explodes it:
   - each `reminders[]` element → one `reminders` row (`id`, `user_id`, `data`, `updated_at` from
     `updatedAt` — **backfill `updated_at = createdAt` or epoch when `updatedAt` is null**, so no
     row has a null merge key; `deleted_at = NULL`).
   - each `lists[]` / `smartLists[]` element → its table (same null-`updated_at` backfill).
   - `settings` → the single settings row.
   - Hidden-source reminders are included (they're normal rows now).
3. **Verify counts and content.** Assert `reminders` row count == blob reminder count (expected 195:
   41 open / 154 completed / 29 recurring per the handoff), lists == 9, and spot-check a few full
   `data` payloads match. **Do not proceed if counts differ.**
4. **Ship the new-model app build** that reads/writes the four tables. On first launch each device
   pulls all rows (cursor = epoch), populating local; confirm both devices show the same 195.
5. **Grace period, then retire `nudge_data`.** Keep the old row untouched for a rollback window (e.g.
   2 weeks). Only after both devices are confirmed healthy on the new model, archive/drop
   `nudge_data`.

### 8.3 Rollback
If the new model misbehaves within the window, the old `nudge_data` row is still intact and the
previous app build still reads it — revert the build, and no data was lost because the blob was never
deleted during migration.

### 8.4 The null-`updatedAt` subtlety
`Reminder.updatedAt` is `String?`. Any reminder created before that field existed, or imported without
it, has `nil`. A merge key cannot be null. The migration backfills `updated_at` from `createdAt`, and
falls back to a fixed old epoch (e.g. `1970-01-01`) if both are nil — meaning "oldest possible", so
the very first real edit from any device wins. Going forward, enforce that every write stamps
`updatedAt` (already true for reminders; add it to list/smart-list writers per §3.1).

---

## 9. Work breakdown (for the eventual build session — not this doc)

**Prerequisites**
- Add `updatedAt` to `ReminderList` and `SmartList`; stamp it in every writer.
- Add `deletedAt: String?` to `Reminder` (and lists/smart-lists); add `deletedAt == nil` to `open()`,
  `sections()`, and every UI query that currently filters on `completed`/`dismissed`.

**Supabase**
- Create 4 tables + RLS policies + `(user_id, updated_at)` indexes.
- Migration/backfill script (§8) with count assertions.
- A scheduled purge of tombstones older than 90 days (pg_cron or a periodic client call).

**Swift (`NudgeStore.swift`)**
- Rewrite `fetchCloud()` → per-table delta pull + merge (§4.1, §5).
- Rewrite `pushCloud()`/`push()` → per-table dirty-set batch upsert incl. tombstones (§4.2).
- Replace `hasPendingPush` boolean with dirty sets (§6.1).
- Rework `deleteReminder`, `undoDelete`, `purgeOldCompleted` to write/clear tombstones (§7).
- Move `backupSnapshot` to per-changing-pull (§6.2).
- Local sync cursor persistence.

**Verification**
- Two-device delete test: delete on Mac, confirm gone on iPhone and **stays gone on the Mac** (the
  exact reproduction that motivated this).
- Concurrent-edit test: edit same reminder on both while offline, reconnect, confirm newer wins.
- Delete-beats-edit test: delete on one, edit on the other, confirm it stays deleted.
- Migration count assertions (195 / 9 / etc.).

---

## 10. Open questions / accepted limitations

- **Clock skew** trusted (§3.3) — accepted for a single-user two-device setup.
- **Settings is whole-row LWW**, not per-key — accepted (small, low-churn).
- **Tombstone purge at 90 days** means a device offline >90 days could resurrect a delete. Accepted;
  90 days is far beyond any realistic offline window for your two always-on devices.
- **Batch-upsert size**: 195 rows is trivial; no pagination needed now. Note it if the list ever grows
  into the thousands.

---
## 11. As built (2026-07-10) — deviations from the design above

The design was implemented, with five deliberate departures. Where this section and the
sections above disagree, **this section is correct** — the code follows it.

### 11.1 "Delete always beats a concurrent edit" was wrong, and broke Undo
§5 locks in *"a delete always wins, even if the live copy's `updated_at` is newer."* §7 then
claims `undoDelete()` works *"since the fresh `updatedAt` is newer than the tombstone's
`deleted_at`."* Both cannot hold. Under §5's absolute rule, deleting a reminder and hitting
Undo brings it back locally, and then the other device — which by now has pulled the
tombstone — applies "delete wins" and it vanishes again on both. The undo silently reverts.

**As built:** later intent wins; an exact tie goes to the delete. A tombstone carries a row
timestamp like anything else. This still fixes the original reproduction (the iPhone's stale
live copy is strictly *older* than the Mac's tombstone, so the delete holds), and Undo works
because a revived item is stamped strictly past its own tombstone.

### 11.2 Two clocks, not one
§3.2 makes the row's `updated_at` a mirror of `Reminder.updatedAt`. But
`RemindersSync.backfillFromApple()` rewrites a reminder's `recurrence`/`url` and
**deliberately does not bump `updatedAt`** (a bumped value would skew the Nudge-vs-Apple
`lastModifiedDate` tiebreak at RemindersSync.swift:378). Ordering sync on `updatedAt` would
strand those edits on one device forever.

**As built:** they are separate concepts.
- `Reminder.updatedAt` (inside `data`) — last *meaningful* edit. Apple's tiebreak. Sync never writes it.
- the row's `updated_at` column — last time the item's *bytes* changed. The only merge key.

### 11.3 Stamps are canonical TEXT, not `timestamptz`
Supabase returns `timestamptz` with six fractional digits, which `ISO8601DateFormatter`
refuses to parse. `updated_at`/`deleted_at` are `text` holding one fixed-width UTC form
(`2026-07-10T13:00:00.123Z`, produced only by `syncStamp()`). Fixed width ⇒ lexicographic
order == chronological order, so PostgREST's `gt.` filter and the client's merge agree
exactly, with zero date parsing on either side.

### 11.4 Tombstones live *beside* the reminders array, not inside it
§5 recommends keeping tombstoned reminders in `reminders` with a `deletedAt` field, filtered
out of every UI query. `reminders` is read at 22 sites across 7 files; one filter that forgets
`deletedAt == nil` renders a ghost.

**As built:** `reminders` stays live-only. Tombstones are a `[String: String]` (id → deletedAt)
in `SyncMeta`. Every delete funnels through `NudgeStore.tombstoneReminders(_:)` — including the
two raw `nudge.reminders.removeAll` calls in `RemindersSync.swift` (`applyDuplicates`,
`reconcile`), which previously deleted with **no trace at all** and were a second, independent
source of the resurrection bug.

### 11.5 The dirty set is derived, not maintained
§4.2/§6.1 say to add each id to a dirty set "wherever `updatedAt` is stamped" — 108 mutation
sites in `NudgeStore` alone. One miss is a silently unsynced edit, and §11.2's backfill has no
`updatedAt` stamp to hang it on.

**As built:** each item carries a content signature (SHA-256 of the exact bytes we'd upload).
Dirty ⇔ `signature != signatureAtLastPush`. No mutation site knows sync exists.

### 11.6 Additional safety not in the design
- **No push before the first successful pull** (`pulledOnce`, persisted). A device whose cache
  is stale — the Mac, offline while the iPhone was edited — would otherwise upload its entire
  stale copy over the newer one on its first sync. The whole-blob clobber, on its way out.
- **Migration seeds as already-pushed.** Adopting the old blob stamps each item from its own
  `updatedAt` (matching the SQL backfill exactly) and marks it clean, so first launch pushes
  nothing. Seeding dirty would give every item a fresh `now()` stamp outranking the real cloud rows.
- **Stamps are monotonic per id**, so an un-delete inside the same millisecond as its tombstone
  still outranks it (see §11.1).
- **Sync is serialised.** The 15s poll and a debounced push both suspend at `await`; on a shared
  `@MainActor` that is enough to interleave into each other's half-merged arrays.
- **Explicit JSON nulls on the wire.** `JSONEncoder` omits nil optionals, and an omitted key in a
  `merge-duplicates` upsert leaves the column untouched — so an un-delete would have uploaded
  `data` while leaving `deleted_at` set, and every other device would go on seeing a tombstone.

### 11.7 Verification
`./ios/Nudge/SyncMergeTests/run.sh` — 26 assertions over the merge rules, including the exact
Mac-delete reproduction, delete-beats-older-edit, tie-goes-to-delete, undo-survives-its-own-
tombstone, absence-is-not-deletion, the backfill case of §11.2, and wire-format nulls. All pass.
iOS, Mac Catalyst and widget targets all build.

### 11.8 Deployment order (unchanged from §8, and it matters)
`supabase/d1/` — run `01_tables.sql`, `02_backfill.sql`, `03_verify.sql` in the dashboard **before** installing
the new app build. The script only ever ADDS tables; `nudge_data` is never touched, and the old
build keeps reading it, so rollback is "reinstall the previous build."

If the new build runs before the tables exist it fails safe: every pull returns 404, `pulledOnce`
stays false, **no push is ever attempted**, and the app stays local-only showing "Offline". No
data is written or lost — but nothing syncs either, so run the SQL first.
