# Handoff — Notion push feature + workspace restructure
**Date:** 2026-07-22
**From:** Cowork session
**To:** Claude Code session

## What this session did

Built a manual, one-way "push to Notion" feature for schoolwork reminders, plus restructured
part of Noah's Notion workspace to support it. **Nothing has been built, tested, committed,
or pushed yet** — that's your job.

## 1. Notion workspace changes (already live — no action needed here)

- Created a new top-level page **"TIHS"** (id `3a574319-20b8-8191-96a7-f045fc325c6c`).
- Moved the existing **"TIHS Daily Study Plans"** database (id `79ed206d-9712-4c4f-9008-809eec3c1c3b`,
  data source `collection://9bb0637e-fd81-4e35-9359-321bb4e8056c`) to be a child of TIHS.
  Its ID and data source ID are unchanged — this move does not affect anything that references
  it by ID (e.g. Noah's existing scheduled task that writes his daily study schedule into it).
  If anything referenced it by URL path rather than ID, that path has changed; ID-based access
  is unaffected.
- Created a new database **"To Do List"** (id in the database URL
  `https://app.notion.com/p/bdd4e8c8b0804f77afdc1aebe339e888`, data source
  `collection://9a88fe32-1c02-439e-873d-f596f29c2230`), also a child of TIHS, alongside the
  study plans database. Schema:
  - `Title` (title)
  - `Due Date` (date)
  - `Notes` (text)
  - `List` (text) — the Nudge list name, e.g. "Study"
  - `Completed` (checkbox)
  - `Location` (text) — location/geofence text, or lat/lng if no text
  - `Nudge ID` (text, hidden utility field) — the reminder's UUID from Nudge; used to match
    rows on re-push so pushing twice never creates duplicates. Not meant to be hand-edited.

**Action needed from you:** confirm with Noah's scheduled study-schedule task (the one that
writes into "TIHS Daily Study Plans" daily) that it's still working after this move. It
should be — Notion database moves don't change IDs — but verify against the actual next run
rather than assuming.

## 2. Feature scope (confirmed with Noah — do not widen without asking)

This is **not** a full sync of every Nudge reminder. Noah was explicit and corrected the
scope twice during this session:

- A reminder is pushed to Notion **only if**: it's in Noah's existing "Study" list (matched
  case-insensitively by list name), **or** it has the new "Push to Notion" toggle switched on
  when adding/editing it (for the rare non-schoolwork reminder he wants there too).
- Nothing else in Nudge is ever sent to Notion. Do not change this to "push all reminders"
  under any circumstance without asking Noah directly first — this was corrected explicitly
  after an initial misunderstanding in this session.
- Push is **manual only** — triggered by a button, never automatic/background. No polling,
  no auto-sync on app launch, nothing.
- Push is **incremental**: only reminders that are new or edited since their last *confirmed
  successful* push are sent (compares `Reminder.updatedAt` vs `Reminder.notionSyncedAt`).
  `notionSyncedAt` is only stamped after a real 2xx response for that specific reminder, so a
  partial failure (network drop, rate limit) never causes a reminder to be silently skipped
  next time — it just gets retried.

## 3. Files changed / added

All under `ios/Nudge/Nudge/` (this is the single shared iOS + macOS-via-Catalyst project —
there is no separate macOS source tree, per Noah's existing `#if targetEnvironment(macCatalyst)`
pattern used throughout).

**New files:**
- `NotionKeyStore.swift` — Keychain storage for the Notion integration token and database ID,
  mirrors `APIKeyStore.swift` (the existing Anthropic key pattern) exactly:
  `WhenUnlockedThisDeviceOnly`, no access group, load/save/clear via `SecItem*` APIs.
- `NotionSyncService.swift` — the actual push logic. Filters reminders to scope, queries
  Notion's database by the `Nudge ID` property to find an existing page (PATCH) or creates a
  new one (POST), maps all Reminder fields onto the schema above, rate-limits itself with a
  350ms pause between reminders (Notion's documented limit is ~3 req/sec average).

**Modified files:**
- `Models.swift` — added `pushToNotion: Bool?` and `notionSyncedAt: String?` to `Reminder`.
  Both optional/nil-default for back-compat with existing stored data.
- `NudgeStore.swift` — added `markPushedToNotion(_ ids: [String])`, called after a push
  completes to stamp `notionSyncedAt` only on confirmed-successful reminders. Also threaded a
  new `pushToNotion: Bool = false` parameter through `saveReminder(...)` and
  `saveReminderThisOccurrenceOnly(...)`.
- `AddReminderView.swift` — new `@State private var pushToNotion`, wired into `load()` and
  both save call sites; new toggle row "Push to Notion" (only shown if `NotionKeyStore.isConfigured`),
  placed next to the existing Pin/Urgent toggles.
- `SyncSettingsView.swift` — new "Notion" settings section: `SecureField` for the integration
  token, `TextField` for the database ID, both Keychain-backed via `NotionKeyStore`, following
  the exact pattern of the existing Anthropic key field above it.
- `ContentView.swift` — new header button (only shown if `NotionKeyStore.isConfigured`) next to
  the existing Settings gear icon, at the top of the app on every tab. Shows a spinner while a
  push is running, disables itself to prevent double-taps, and shows a bottom toast on
  completion ("Pushed N to Notion" / "Pushed N, M failed — try again" / "Nothing new to push").

## 4. What you need to do

1. **Add the two new files to the Xcode target.** Cowork's sandbox can create files on disk
   but cannot modify the `.xcodeproj` target membership — `NotionKeyStore.swift` and
   `NotionSyncService.swift` currently exist as files but are very likely NOT yet added to the
   Nudge target in `Nudge.xcodeproj/project.pbxproj`. Add them (same target as
   `APIKeyStore.swift`) or the build will fail to find the symbols, or silently exclude the code.
2. **Build and fix any compile errors.** This was written carefully against the existing
   patterns in the codebase but has not been compiled or run. Check especially:
   - `NotionSyncService`'s JSON property-building matches Notion API's actual expected shapes
     (I used the documented v2022-06-28 shapes but haven't tested against a live call).
   - The `Theme.hairline`, `Theme.surface`, `PressableStyle` references in the new header
     button match what's already used elsewhere in `ContentView.swift` (they should — copied
     from the adjacent `iconButton` helper — but verify).
3. **Test manually**, ideally with Noah watching:
   - Set a Notion integration token + the To Do List database ID in Settings.
   - Share the "To Do List" database with that integration in Notion (Noah needs to do this
     in the Notion UI — "..." menu → Connections → add the integration. This can't be done
     via API and needs to happen before any push will succeed).
   - Mark a reminder as "Study" list or toggle "Push to Notion", tap the header button, confirm
     it lands correctly in Notion with all fields.
   - Push again with no changes — confirm it reports "Nothing new to push" and does not
     duplicate the row.
   - Edit the reminder, push again — confirm it updates the same row (not a new one).
4. **Pre-existing issue spotted, not touched:** `NudgeStore.swift` around line 1212 and 1316
   has malformed comments (`/ A geofence is...` and `/ 1) Detach THIS...` — missing the second
   `/`). These predate this session's changes; flagging so you can decide whether to fix them,
   but they weren't introduced by this work and I left them alone since Noah didn't ask for
   that.
5. **Commit and push.** Per project convention: commit with a clear message, push, then **at
   the end, remove any locks or stale locks** so the repo is clean and smooth for next time.
6. **Verify the study-schedule scheduled task** (see section 1) still writes correctly into
   "TIHS Daily Study Plans" after the Notion move. This is a separate system from anything in
   this handoff — Noah mentioned it as a reminder to check, not something this session changed
   — but it touches the same Notion page structure, so confirm before considering this done.

## 5. Security notes

- Notion integration token is a real secret (workspace read/write within its shared scope). It
  is Keychain-only (`WhenUnlockedThisDeviceOnly`), never in UserDefaults, never logged, never
  in this handoff doc or committed to git.
- The database ID is not secret but is stored alongside the token in the Keychain for
  simplicity (tied to the same "is Notion configured" state).
- The "Nudge ID" written into Notion is just the reminder's local UUID — not sensitive, not a
  credential, doesn't leave Noah's own Notion workspace.
- No automatic/background network calls were added — push only happens on an explicit user tap.
