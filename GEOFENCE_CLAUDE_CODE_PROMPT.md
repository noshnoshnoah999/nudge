# Claude Code Prompt — Implement Location-Triggered Reminders (Geofencing) in Nudge

Paste everything below into Claude Code, run from the Nudge repo root. It compiles and can be device-tested there. This spec is build-ready and all design decisions are locked (see `GEOFENCE_SPEC.md`). **Do not redesign — implement.**

---

## Context you must respect

- **Architecture:** iOS + Mac share one SwiftUI target (`ios/Nudge/Nudge/`). The **web app is RETIRED** — do NOT touch `index.html`. There is **NO SQL migration**: reminders are stored as a single JSON blob in Supabase `nudge_data.data` (jsonb), encoded from the `NudgeData`/`Reminder` `Codable` structs in `NudgeStore.swift`. New optional Swift fields become new JSON keys automatically — old blobs decode fine, no schema change, no new columns.
- **Existing code (verified):**
  - `Models.swift` → `struct Reminder` already has `location: String?`, `lat: Double?`, `lng: Double?` (currently just a Maps bookmark). Reuse these — do NOT add new coordinate fields.
  - `LocationPickerView.swift` → `MKLocalSearchCompleter` picker, requests ZERO location permission (search only). Do NOT change its search behaviour or add permission requests inside it.
  - `Notifications.swift` → central scheduler, `registerCategories()`, a `UNUserNotificationCenterDelegate` already wired for Complete/Snooze actions, uses `UNCalendarNotificationTrigger`. Reuse its categories so location notifications get the same tap-actions.
  - `NudgeStore.swift` → owns `reminders`, encodes/decodes the `nudge_data` blob, upserts on `user_id`.
  - `NudgeApp.swift` → app entry / scene phase.
  - `Info.plist` at `ios/Nudge/Nudge/Info.plist` → currently has NO `NSLocation*` keys.

## Locked decisions (do not deviate)

1. Mechanism: **`CLLocationManager` region monitoring** (NOT `UNLocationNotificationTrigger`).
2. Permission: **Always**, via two-step escalation — When-In-Use first, then upgrade to Always.
3. If only When-In-Use granted: **still monitor**, show honest copy, offer Settings deep link. Do NOT disable geofencing.
4. **iPhone is the only platform that fires** in v1. Mac = store fields + label only (no monitoring). No web.
5. Region cap: **20 max**, keep the **nearest 20** to last known location. Show a UI note when capped.
6. Radius: **fixed 150m** in v1 (clamp to `maximumRegionMonitoringDistance`). `geofenceRadius` field is reserved, no slider.
7. A reminder may have **both** a due time and a geofence — both fire independently.
8. On-device geofencing is **fully local** — no new data transmission. The coordinate already syncs for display under existing RLS.

---

## TASK 1 — Model fields (`ios/Nudge/Nudge/Models.swift`)

In `struct Reminder`, immediately AFTER the `var lng: Double?` line, add:

```swift
    // Location-triggered reminders (geofencing). All optional for back-compat with old blobs.
    var geofenceEnabled: Bool? = nil   // true = fire a notification on arrive/leave at lat/lng
    var geofenceTrigger: String? = nil // "arrive" | "leave"  (nil treated as "arrive")
    var geofenceRadius: Double? = nil  // metres; nil → default 150. Reserved for future UI.
```

Do not change any `CodingKeys` unless the struct uses an explicit `CodingKeys` enum that lists every field — if it does, add the three keys; if it relies on synthesized keys, leave it. **Check and match whatever pattern the file already uses.**

---

## TASK 2 — New file `ios/Nudge/Nudge/LocationMonitor.swift`

Create a single long-lived `@MainActor` object owning one `CLLocationManager`. It must:

- Be a singleton (`static let shared`) instantiated at app launch so the OS can relaunch the app for region events.
- Set `manager.delegate = self`, `manager.allowsBackgroundLocationUpdates = false` (we never stream location).
- Expose `requestWhenInUse()` and `requestAlways()` for the two-step escalation, plus a published `authStatus`.
- Expose `sync(reminders:near:)` that:
  1. Stops monitoring all current `monitoredRegions`.
  2. Filters eligible = `geofenceEnabled == true` && not `completed` && not `dismissed` && `lat`/`lng` non-nil.
  3. If eligible > 20 and a `near` location is known, sort by distance ascending and keep the nearest 20; otherwise `prefix(20)`.
  4. For each, build a `CLCircularRegion(center:radius:identifier:)` with `identifier == reminder.id`, `radius = min(geofenceRadius ?? 150, manager.maximumRegionMonitoringDistance)`, set `notifyOnEntry`/`notifyOnExit` from `geofenceTrigger` ("arrive" → entry, "leave" → exit), then `manager.startMonitoring(for:)`.
- Implement `didEnterRegion` / `didExitRegion` (nonisolated, hop to `@MainActor`) → look up the reminder by `region.identifier`, build a `UNMutableNotificationContent` (title = reminder title, body e.g. "You've arrived at {location}" / "You've left {location}"), set the category identifier to the SAME category `Notifications.registerCategories()` uses so Complete/Snooze work, and deliver with a `nil` trigger (fires immediately) via `UNUserNotificationCenter.current().add(...)`.
- Implement `locationManagerDidChangeAuthorization` → update `authStatus`.

Use the sketch in `GEOFENCE_SPEC.md` §7.1 as the starting point, but wire the `fire(...)` body fully (the spec left it as a stub) and reuse the real category identifier from `Notifications.swift` — read that file to get the exact string; do not invent one.

---

## TASK 3 — Hook points

- **`NudgeApp.swift`**: reference `LocationMonitor.shared` at launch (so it exists for OS relaunch). On scene phase `.active`, call `LocationMonitor.shared.sync(reminders: store.reminders, near: <last known or nil>)`. If no cheap last-known location is available, pass `nil` (cap still applies via `prefix(20)`).
- **`NudgeStore.swift`**: after any mutation that adds/edits/completes a reminder (find the existing save/persist choke point), call `LocationMonitor.shared.sync(...)`. One call at the persist point is enough — don't scatter it.
- **Do NOT** add `startUpdatingLocation` anywhere.

---

## TASK 4 — Permissions (`ios/Nudge/Nudge/Info.plist`)

Add these two keys (strings, user-facing):

- `NSLocationWhenInUseUsageDescription` = `Nudge uses your location to remind you when you arrive at or leave a place.`
- `NSLocationAlwaysAndWhenInUseUsageDescription` = `Allow Always so Nudge can remind you at a place even when the app is closed.`

Do NOT add `UIBackgroundModes: location` unless on-device testing proves region events don't fire without it (region monitoring normally relaunches the app without it). If you must add it, note why in the handoff.

---

## TASK 5 — UI (`ios/Nudge/Nudge/AddReminderView.swift`)

In the existing Location section (where `LocationPickerView` is invoked), once `lat`/`lng` are set, reveal:

- A master toggle **"Notify at this place"** bound to `geofenceEnabled` (default OFF, so existing bookmark behaviour is unchanged).
- A segmented control **Arrive ⇄ Leave** bound to `geofenceTrigger` (default "arrive"), shown only when the toggle is on.
- The FIRST time the toggle is switched on, run the permission escalation: `LocationMonitor.shared.requestWhenInUse()`, then request Always. If denied, show inline text: `Location access is off — this reminder won't fire at the place.` with an **Open Settings** button (`UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`).
- If only When-In-Use was granted, show: `May only fire while Nudge is open.`
- **Mac (`#if os(macOS)`):** render the place + a NON-interactive label `📍 Location reminder — fires on your iPhone.` Do not show the toggle or request permission on macOS in v1.
- Keep the reminder fully saveable regardless of permission outcome.

Copy must be honest — no "instant" or guaranteed-fire promises. Region events can lag a minute or two; that's expected OS behaviour.

---

## TASK 6 — Build, device-test checklist (do what you can, note the rest for Noah)

- Compiles clean for iOS and macOS targets.
- Grant path: toggle on → When-In-Use → Always prompts appear in order.
- Deny path: reminder still saves; inline copy + Open Settings shown.
- Arrive vs Leave register the correct `notifyOnEntry`/`notifyOnExit`.
- >20 eligible reminders → only 20 monitored, nearest-first, UI note shown.
- App-closed firing (Noah must walk in/out of a real region — flag as manual test).
- Mac shows label only, requests no permission, doesn't crash.

---

## TASK 7 — Commit, push, cleanup (per project rules)

1. `git add -A` the changed Swift + Info.plist (NOT `index.html`).
2. Commit: `Add location-triggered reminders (geofencing): CLLocationManager region monitoring, Always-perm escalation, arrive/leave toggle (iOS); Mac label-only`.
3. Push to `origin/main`.
4. Write a handoff MD (`GEOFENCE_IMPL_HANDOFF.md`) summarising what was built, what still needs Noah's on-device walk test, and any deviations.
5. **After committing and pushing, remove any git lock / stale lock files (e.g. `.git/index.lock`, `.git/refs/**/*.lock`) so the next session starts clean.**

---

## Safety notes (Noah's #1 priority)

- No secrets or API keys involved in this feature — nothing for Noah to paste anywhere.
- Geofencing is 100% on-device; no new data leaves the phone. The coordinate already syncs for display under existing RLS.
- The only privacy surface is the Always permission — handled with honest, in-context copy. Never request Always cold at launch.
- Fail-safe: if permission is denied or monitoring fails, the reminder still exists and shows; it just won't fire at the place. No silent data loss.
