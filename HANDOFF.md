# Nudge — Handoff

_Last updated: 2026-06-24_

A reminders app that exists as **two clients over one shared data blob**: a native
SwiftUI app (iPhone + Mac Catalyst) and a web PWA. This doc is the orientation for picking
up the iOS app cold.

---

## 1. What Nudge is

- **iOS / Mac app** — SwiftUI, target `ios/Nudge/Nudge.xcodeproj`, bundle id `uk.flouty.Nudge`.
  Two targets: the **app** (iOS + Mac Catalyst) and the **NudgeWidgets** extension
  (home-screen widgets, Lock Screen quick-add, a Control Center control, and the AlarmKit
  Live Activity).
- **Web PWA** — separate codebase, same backend.
- **Backend** — a single Supabase row (`nudge_data`) holding the *entire* app state as one
  JSON blob (reminders, lists, smart lists, settings). Every client reads/writes the whole
  blob. The Supabase project is **shared with StudyTrack**; the Finance/budget app writes
  into the same blob too (see §5). Anon key + URL are hard-coded in `NudgeStore.swift`
  (public-tier key, intentional).

### Data flow
```
iPhone ⇄ ┐
Mac     ⇄ ┼── Supabase nudge_data (one JSON blob) ⇄ web PWA
StudyTrack/Finance write here too
```
`NudgeStore` polls the blob every ~15s, merges, and pushes debounced writes. Local edits are
guarded by `hasPendingPush` so an in-flight cloud copy can't stomp them, and a rotating local
backup (`backups/`, last 60) is taken before any overwrite.

---

## 2. Build & deploy

**Signing:** free Apple team — provisioning expires every 7 days, so reinstalls are frequent
and routine. Build with `-allowProvisioningUpdates`. The convention in this project is to
**always deploy to BOTH the iPhone and the Mac after every change** (no need to ask).

**iPhone** (device id `73562BAB-DA59-5AB0-A722-8AACE1D8820C`, iPhone 17 Pro, on iOS 26):
```bash
cd ios/Nudge
xcodebuild -project Nudge.xcodeproj -scheme Nudge \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
APP=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-iphoneos/Nudge.app | head -1)
xcrun devicectl device install app --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C "$APP"
xcrun devicectl device process launch --terminate-existing \
  --device 73562BAB-DA59-5AB0-A722-8AACE1D8820C uk.flouty.Nudge
```
The install occasionally fails with `CoreDeviceError 4000` — just retry (a 2–3x loop is built
into the deploy commands used in session). The device is usually on **Wi-Fi (CoreDevice)**, not
USB, so `pymobiledevice3` (USB/usbmux) **cannot** reach it for crash logs — see §6.

**Mac (Catalyst):**
```bash
cd ios/Nudge
xcodebuild -project Nudge.xcodeproj -scheme Nudge \
  -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates build
MACAPP=$(ls -td "$HOME/Library/Developer/Xcode/DerivedData/Nudge-"*/Build/Products/Debug-maccatalyst/Nudge.app | head -1)
pkill -x Nudge; open "$MACAPP"
```

> **Always verify the iOS build** when touching anything AlarmKit-related — that code is
> compiled out of the Mac build (see §4), so only the iOS build catches those errors.

---

## 3. Key files (iOS app — `ios/Nudge/Nudge/`)

| File | Role |
|------|------|
| `NudgeApp.swift` | `@main`, AppDelegate, **scene delegate** (reads the launching notification — see §6). |
| `NudgeStore.swift` | The data layer: load/merge/push the Supabase blob, all reminder mutations, backups, smart reschedule. |
| `Models.swift` | `Reminder`, `ReminderList`, `NudgeData`, etc. Mirrors the web JSON shape. |
| `ContentView.swift` | Root UI, tab bar (Home/Today/Overdue/Upcoming/Lists/Search), `processPendingNotification()`. |
| `AddReminderView.swift` | Create/edit sheet (incl. the **Urgent** toggle). |
| `Notifications.swift` | `UNUserNotificationCenter` scheduling + delegate + action handling. |
| `AlarmService.swift` | **AlarmKit** urgent alarms (iOS-only). |
| `CalendarService.swift` | EventKit — event-conflict checks, birthdays. |
| `AIScheduler.swift` | Claude API smart-reschedule (raw URLSession, structured output). |
| `SplashView.swift` | The bell launch animation (`RootContainer` + `SplashView`). |
| `TimetableView.swift`, `CleanUpView.swift`, `DedupPreviewView.swift`, `MiniCalendar.swift` | Feature screens. |
| `Changelog.swift` | The in-app "What's New". **Keep it updated when you ship user-facing changes.** |

Shared between app + widget (`ios/Nudge/Shared/`): `AppRouter.swift` (navigation intents),
`QuickAddIntent.swift`, `NudgeAlarm.swift` (AlarmKit metadata type).

> **pbxproj note:** the `Nudge/` folder is a *synchronized* group (files auto-included in the
> app target). `Shared/` files are **explicit** — adding one means editing
> `project.pbxproj` to add it to *both* the app and widget Sources phases (see how
> `NudgeAlarm.swift` / `AppRouter.swift` are wired).

---

## 4. Urgent reminders / AlarmKit Live Activities (iOS 26)

Mark a reminder **Urgent** (toggle in `AddReminderView`) → Nudge schedules a real **AlarmKit**
alarm that rings + shows a Live Activity / Dynamic Island at the due time even when the app is
closed, Apple-Reminders-style (Snooze + slide-to-stop + a "Snooze 8:57 min" countdown).

- `Reminder.urgent: Bool?` carries the flag.
- `AlarmService.NudgeAlarms` — `authorize()`, `schedule()`, `cancel()`. Alarm id is an
  MD5-derived stable UUID from the reminder id (so schedule/cancel match).
- Scheduled on save (urgent + future *timed* due); cancelled on complete/delete.
- Permission is requested the moment the **Urgent** toggle flips on (`AddReminderView`
  `.onChange`).
- Live Activity UI: `NudgeAlarmLiveActivity` in `NudgeWidgets.swift`, switches on
  `context.state.mode` (`.alerting` / `.countdown(let cd)` → `cd.fireDate` / `.paused`).

### Gotchas that cost real time here (don't relearn them)
- **All AlarmKit code is gated `#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)`.**
  `canImport(AlarmKit)` is *true* on Catalyst but the types are *unavailable* there, so the
  `canImport` check alone is not enough — you need the `!macCatalyst` too.
- **`NSAlarmKitUsageDescription` must live in a real `Info.plist`**, not an
  `INFOPLIST_KEY_…` build setting. Xcode's auto-Info.plist generation only honours an
  allowlist of keys and silently drops new ones like this — and AlarmKit then denies
  authorization with **no prompt**. The key is in `ios/Nudge/Nudge/Info.plist`
  (`INFOPLIST_FILE = Nudge/Info.plist`, kept merged with generation), and that file is
  excluded from the synchronized group's resource copy via a
  `PBXFileSystemSynchronizedBuildFileExceptionSet` (otherwise "Multiple commands produce
  Info.plist").

---

### Mac Catalyst calendar gotcha (cost real time, 24 Jun)
EventKit on **Mac Catalyst needs the `com.apple.security.personal-information.calendars`
entitlement** — the `NSCalendarsFullAccessUsageDescription` string alone is enough on iOS but
NOT on Catalyst. Without it `requestFullAccessToEvents()` throws immediately (swallowed by
`try?`), no prompt ever shows, and the app never even appears in System Settings → Privacy →
Calendars. The entitlement lives in `ios/Nudge/Nudge/Nudge.entitlements`, wired **SDK-scoped**
via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` so it only applies to the Catalyst build (keeping it
off the iOS build avoids free-account provisioning issues — that build has no entitlements file
and must stay that way). The app is **not sandboxed** (no container, no `app-sandbox` key) — do
NOT add `com.apple.security.app-sandbox`, it would break Supabase networking without a
`network.client` grant.

## 5. Hiding StudyTrack / Finance reminders

The shared blob contains reminders authored by other apps (`source == "studytrack"` or
`"finance"`). These are **hidden from Nudge's UI and notifications** but must **not** be
deleted from the blob (the other apps own them).

Implementation (`NudgeStore`): `apply()` partitions the blob into the visible `reminders`
array and a private `hiddenSource` array. **Every cloud/cache/backup write uses
`fullReminders()` (= `reminders + hiddenSource`)** so the hidden ones round-trip untouched.
Change-detection uses `sameReminders()` (order-insensitive) against the full set. If you add a
new code path that writes the blob, it **must** use `fullReminders()`, never `reminders`.

---

## 6. Notification-tap → open the right reminder (and the crash saga)

Tapping a Nudge notification should open the app **to that specific reminder**, on cold launch
too. This was the source of a recurring `SIGABRT` in
`_updateSnapshotAndStateRestoration`. Current working design:

- The `UNUserNotificationCenter` **delegate is set late** (in `NotificationManager.attach`,
  after the SwiftUI scene exists) — setting it during `didFinishLaunching` delivers a launch
  tap into a half-built window and UIKit asserts.
- Because the delegate is late, a **cold-launch** tap is read instead from the scene's
  connection options: `NudgeSceneDelegate.scene(_:willConnectTo:options:)` reads
  `connectionOptions.notificationResponse` → stashes it in the non-`@Published`
  `NotificationManager.pendingColdTap`. `ContentView.processPendingNotification()` drains it
  after the first `refresh()` and opens the reminder.
- **Urgent reminders re-triggered the crash** via a new route: AlarmKit *wakes the app in the
  background* to manage the alarm, so by the time the user taps the notification the store is
  already attached (`nudge != nil`) and `handle()` took the warm path, writing `@Published`
  router state **synchronously during the background→foreground state-restoration window**.
  Fix: in the warm path, **every observed-state write is deferred one runloop tick**
  (`DispatchQueue.main.async`) so it lands after the restoration transaction.

**Rule of thumb:** never mutate `@Published` state synchronously inside the notification
delegate / launch path. Stash into a plain holder, or defer a tick.

**Getting crash logs:** the device is on Wi-Fi, so `pymobiledevice3` (USB only) reports
"Device is not connected" and `~/Library/Logs/CrashReporter/MobileDevice/` only populates if
Xcode/Console has pulled them. To capture a device crash, either plug in via USB or open
Xcode → Window → Devices & Simulators → View Device Logs.

---

## 7. Recent commits (this session)

```
6807fbe Apple-style urgent alarm (Snooze + countdown), hide budget/study reminders, faster splash
6b33f06 Fix urgent-reminder notification-tap crash (background-launch state restoration)
21e06c1 Fix: AlarmKit permission prompt never appeared (usage key dropped from Info.plist)
03104c8 Urgent: request AlarmKit permission the moment the toggle is switched on
03d5d42 Live Activities: 'Urgent' reminders ring via AlarmKit (iOS 26)
06592b8 Open the tapped reminder on cold launch via scene connectionOptions
```

---

## 8. Open / needs on-device verification

- **AlarmKit alarm rendering** — the alarm ringing, the Snooze countdown, and the exact
  Live Activity / Dynamic Island layout can only be confirmed on the physical iPhone (can't be
  render-tested from a build machine). Custom widget UI vs AlarmKit's own template needs a
  visual check.
- **"Reschedule" button on the alarm Live Activity** (as in Apple Reminders) is **not** built
  yet — would need a `secondaryIntent` / `LiveActivityIntent`.
- **`Changelog.swift`** should get a "What's New" entry for the urgent-alarm + hidden-source
  changes before the next user-facing release.
- Tracked TODO: pull the real "Send to Mum" ¥ amount from the budget app into Nudge.
- `reinstall_nudge.sh` profile-purge step is unreliable on the free account; the direct
  `xcodebuild` + `devicectl` path above is the dependable route.
