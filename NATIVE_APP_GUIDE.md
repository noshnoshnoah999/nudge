# Building Native iOS + Mac Apps: Lessons from Nudge

**TL;DR:** Nudge is a web PWA + unified SwiftUI iOS/Mac Catalyst app over a shared Supabase blob. This document captures what works, what doesn't, and how to do it. All patterns below are verified against the real Nudge code.

---

## Architecture

### The Blob Model
- **One Supabase project** per app, one row per user holding the entire app state as a JSON blob (`data` JSONB column).
- **Local-first:** iOS/Mac reads the blob into memory at launch, edits locally, pushes the whole blob back.
- **Web app** (PWA in index.html) hits the same Supabase endpoint, works offline via Service Worker.
- **No REST API per entity.** Just fetch/upsert the whole blob. Simple to reason about.

### Code Sharing
- **Shared folder** (`ios/Nudge/Shared/`): code used by both the app and the widget extension — data models, helpers (date parsing, file storage). Do NOT put SwiftUI views here.
- **App folder** (`ios/Nudge/Nudge/`): iOS views + logic. Mac builds the same target as Catalyst (one .xcodeproj scheme → both platforms). Use `#if targetEnvironment(macCatalyst)` for the rare Mac-only branch.

### Supabase Setup (Nudge's actual schema)
```sql
CREATE TABLE nudge_data (
  user_key UUID PRIMARY KEY,    -- a hardcoded per-user UUID, not a real auth user
  data JSONB NOT NULL,          -- entire app state as JSON
  updated_at TIMESTAMPTZ NOT NULL
);
```
- Fetch: `GET /rest/v1/nudge_data?user_key=eq.<uuid>&select=data`
- Write: `POST /rest/v1/nudge_data` with header `Prefer: resolution=merge-duplicates` (upsert).
- **Auth:** Nudge uses the Supabase **anon key** (public-tier, lives in the binary) + a hardcoded `user_key` UUID — no sign-in flow. Fine for a single-user personal app. For multiple users, add real Supabase Auth + RLS.

### Conflict Resolution (how Nudge actually does it)
On `refresh()`, after fetching the cloud blob:
- If `hasPendingPush` (we have un-uploaded local edits) **OR** the cloud blob equals local (nothing changed) → **don't apply** the cloud copy (keep local, avoid churn).
- Otherwise → cloud wins: back up local first, then apply the cloud blob.

It does **not** compare `updated_at` timestamps on fetch — the `hasPendingPush` flag protects un-synced local edits. Every local mutation bumps the reminder's `updatedAt` so external (e.g. Apple) merges resolve correctly.

---

## Tech Stack

### SwiftUI + Foundation
- **SwiftUI only.** No UIKit wrappers except where unavoidable (Nudge's `LockShield` uses a `UIWindow` for app-lock because a SwiftUI overlay can't sit above presented sheets).
- **@MainActor** store, async/await + Combine. No third-party state libraries.

### Persistence
- **UserDefaults:** small prefs only (theme, app-lock, pinned lists). Not app data.
- **FileManager:** backups (JSON snapshots) + image attachments. **Create dirs once** (`lazy var` / `static let`), not on every access — repeated `createDirectory` triggers Xcode's "excessive I/O" warning.
- **Codable:** encode/decode the whole blob. Default missing fields so old cloud JSON still decodes when you add fields.

### Networking
- **URLSession only.** POST the blob, GET the blob.
- Supabase **anon key** (hardcoded) on both `apikey` and `Authorization: Bearer <anon-key>` headers, plus a per-user UUID row key. No login screen needed for a personal app.

### Apple Reminders Sync (iOS only, optional)
- **EventKit:** push Nudge reminders to Apple Reminders so they sync to iCal/other apps; merge bidirectionally.
- **Gotcha:** Apple's `lastModifiedDate` wins for Apple-side edits; Nudge's `updatedAt` wins for Nudge-side. Be explicit about order, and extract any "advance" logic (e.g. routines) into a helper so an Apple-completed item doesn't silently die.

### Notifications
- **UNUserNotificationCenter:** local notifications, no remote push. Schedule off each item's due date; remove on complete.
- **Action buttons** (Complete/Snooze): the handler runs in the **background** — you MUST `await` an immediate push there (see persistNow below), or the change is lost when iOS suspends the app.
- Update the app icon badge with the overdue count.

---

## Project Structure
```
my-app/
├── ios/MyApp/
│   ├── MyApp.xcodeproj          # one project, two platforms (iOS + Mac Catalyst)
│   ├── MyApp/                   # iOS-specific views & logic
│   │   ├── ContentView.swift    # main tab view
│   │   ├── AddReminderView.swift
│   │   ├── MyAppStore.swift     # @MainActor, all state + sync
│   │   ├── Theme.swift
│   │   └── Notifications.swift
│   ├── MyAppWidgets/            # widget extension (Home + Lock Screen)
│   ├── Shared/                  # models + helpers used by app AND widget
│   └── Info.plist
├── index.html                   # PWA, same data model/blob
├── NATIVE_APP_GUIDE.md          # this file
└── NATIVE_APP_PROMPT.md         # kickoff prompt
```

---

## Key Patterns

### State Management
```swift
@MainActor
final class MyAppStore: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var syncState: String = "Synced"
    private var hasPendingPush = false
    private var pushTask: Task<Void, Never>?

    func refresh() async { /* GET blob; apply only if !hasPendingPush && cloud != local */ }

    func persist(notify: Bool = true) {        // debounced ~700ms upsert
        // cache locally, setSync("Syncing…"), hasPendingPush = true
        // pushTask?.cancel(); pushTask = Task { sleep 700ms; await push(blob) }
    }

    /// Awaited immediate push — REQUIRED for background notification actions.
    func persistNow() async {
        pushTask?.cancel()
        // cache blob; hasPendingPush = true; await push(blob)
    }
}
```

**Guard sync churn:** only publish `syncState` when it changes — otherwise the background poll re-renders every observer (including an open edit sheet, dropping its keyboard focus):
```swift
private func setSync(_ s: String) { if syncState != s { syncState = s } }
```

### Backups
- Snapshot the blob to `Documents/backups/` on launch + every sync (before a cloud copy overwrites local). Keep ~60, throttle to one auto-backup per 10 min.
- Surface in Settings ("Last backup: 2m ago · 47 kept") and offer one-tap restore.

### Undo
- Hold the **single last-deleted item** in memory (`recentlyDeleted`) — no full history needed.
- **Defer asset cleanup:** don't purge a deleted item's photos until `finalizeDelete()` runs (after the undo window), so undo can restore them.

### Biometric Lock (Face ID / Touch ID)
- `LAContext().evaluatePolicy(.deviceOwnerAuthentication)`, fall back to passcode, return `true` if unavailable (never lock the user out).
- **Single-prompt guard:** the Face ID system UI briefly flips the scene inactive→active, and the `.active` handler can fire a *second* prompt while the first is pending — two concurrent `evaluatePolicy` calls jam iOS (stuck Face ID). Use an `isAuthenticating` flag so only one runs at a time; on cancel/fail, keep the lock shield up with an Unlock button to retry.

### Asset Storage
- Images/attachments live in `Documents/<entity-id>/` (local, not in the cloud blob).
- Store only the file URL string in the item's JSON. On delete, remove the file + the reference together.

---

## Common Gotchas & Fixes

| Problem | Cause | Fix |
|---------|-------|-----|
| **Text field won't focus on iPhone (works on Mac)** | `TextField(axis: .vertical)` inside a `ScrollView` doesn't become first responder on iOS. | Plain single-line `TextField`. If multi-line needed, add `@FocusState` + `.simultaneousGesture(TapGesture().onEnded { focused = true })`. |
| **Face ID glitches / sticks on open** | Concurrent `evaluatePolicy` (scene inactive→active fires a 2nd prompt). | `isAuthenticating` guard; one prompt at a time. |
| **Notification "Complete" doesn't stick** | Action handler relied on the debounced push; iOS suspends the app before it fires, then refresh() overwrites it. | `await store.persistNow()` at the end of the action handler. |
| **Scrolling is glitchy** | Per-card `DragGesture` competes with `ScrollView` pan. | No swipe-to-delete drag; use long-press context menu / edit sheet. |
| **Store churn drops keyboard focus** | Poll sets `syncState` every cycle → re-renders the edit sheet. | Guard `setSync()`; also pause the poll while an edit sheet is open. |
| **"Excessive I/O" Xcode warning** | `createDirectory` in a computed property hit on every access/render. | `lazy var` / `static let` closure — create once. |
| **7-day signing doesn't reset on reinstall** | `xcodebuild` reuses a cached provisioning profile. | Move the cached profiles aside before building so `-allowProvisioningUpdates` mints fresh ones; restore them if the build fails. |
| **Reinstall silently installs a stale app** | A build failure hidden by a piped `tail` (pipeline exit code). | `set -o pipefail` around the build; abort on failure. |
| **iPhone build: "No Accounts"** | Xcode signed out of your Apple ID. | Xcode ▸ Settings ▸ Accounts ▸ + ▸ Apple ID, then rebuild. |
| **App won't launch after 7 days** | Free-team provisioning profile expired. | Reinstall every ~5 days to reset; or pay for a real Apple Developer team. |

---

## Deployment

### Free-Signing (7-day cycle)
- No paid account needed; use Xcode "Automatically manage signing" with a personal Apple ID.
- App stops launching after 7 days; reinstall resets it.
- **Script it** (`reinstall_app.sh`): move cached profiles aside → build iOS (abort on failure) → install to iPhone via `devicectl` → build + relaunch Mac Catalyst. The Nudge script also accepts a network-paired iPhone (`available (paired)`, not just cabled `connected`).

### Testing MUST be on iPhone
Mac Catalyst is fast to test but hides iPhone-only bugs (vertical TextField focus, Face ID, touch). After every change: reinstall to **both**, then verify the feature on the **iPhone**.

### Widgets
- Separate target; share `Shared/` for models + data access.
- Widgets are read-only snapshots — use **AppIntents** to send actions (e.g. quick-add, tick off) back to the app.
- Home Screen + Lock Screen are separate kinds; Lock Screen needs a compact layout.

---

## Development Workflow

**Daily loop:** edit a Swift file → run the reinstall script → **test on iPhone** → commit.

**Before shipping:** compile clean on Catalyst; run on iPhone (golden path + offline + interrupted sync + stale profile); verify backups + restore; notifications fire on time and their actions persist; Face ID unlock is smooth; widgets work.

---

## Resources
- Apple: [SwiftUI](https://developer.apple.com/xcode/swiftui/), [EventKit](https://developer.apple.com/documentation/eventkit), [LocalAuthentication](https://developer.apple.com/documentation/localauthentication), [WidgetKit](https://developer.apple.com/documentation/widgetkit).
- Supabase: [Swift SDK](https://github.com/supabase/supabase-swift), [RLS](https://supabase.com/docs/guides/auth/row-level-security).
- Reference implementation: `ios/Nudge/`.
