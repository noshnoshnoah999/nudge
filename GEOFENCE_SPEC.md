# Nudge — Location-Triggered Reminders (Geofencing) — Technical Spec

**Status:** Build-ready. All §10 decisions resolved with Noah (2026-07-10). No code written yet — awaiting go-ahead to implement.
**Date:** 2026-07-10
**Author:** Claude (Cowork), grounded in the current Nudge codebase.
**Decisions locked with Noah:** Full technical spec · Web/Mac = store-only + label · Permissions = Always-on, explained.

---

## 0. What exists today (verified in code, not assumed)

Before proposing anything, here is what Nudge already has, so the spec extends reality instead of reinventing it:

- **Data model** (`ios/Nudge/Nudge/Models.swift`, `struct Reminder`): already has `location: String?`, `lat: Double?`, `lng: Double?`. Comment on `location` literally says `// a place / address (tap → Maps)`. So today a location is a *bookmark*, not a trigger.
- **Location picker** (`ios/Nudge/Nudge/LocationPickerView.swift`): an Apple-Reminders-style search picker using `MKLocalSearchCompleter` + `MKLocalSearch`. Its header comment states: *"No location permission needed (search only — we never read the user's location)."* Returns `(name, lat, lng)` via `onSelect`. **This is the key fact:** Nudge currently requests **zero** location permission.
- **Notifications** (`ios/Nudge/Nudge/Notifications.swift`): a central `Notifications` scheduler. All reminders fire via `UNCalendarNotificationTrigger` (date-based). Auth is requested in `enable()` with `requestAuthorization(options: [.alert, .sound, .badge])`. There is a `registerCategories()`, a debounced `reschedule()`, and a `UNUserNotificationCenterDelegate` already wired for actions. **There is no `UNLocationNotificationTrigger` and no `CLLocationManager` anywhere.**
- **Info.plist** (`ios/Nudge/Nudge/Info.plist`): **no** `NSLocation*` keys, **no** `UIBackgroundModes` location entry. Confirmed by grep — none present.
- **Web** (`index.html`, single-file PWA) and **Mac** (same SwiftUI target as iOS) share the `Reminder` shape and sync via Supabase (recent commits: magic-link Auth + RLS-ready sync).

**Implication:** the gap is real and narrow. Nudge stores the coordinate but never watches for arrival/departure. Adding geofencing = add region monitoring + a new trigger path + a permission ask + one UI toggle + three schema fields. The picker and the coordinate storage are already done.

---

## 1. Goal & non-goals

**Goal:** "Remind me when I *arrive at* (or *leave*) place X." Fires as a local notification even when the app is closed. Examples: Shin-Kiba station, a shop, school.

**Non-goals (this version):**
- No "remind me when I'm near any of these" smart clustering.
- No time-windowed geofences ("only between 8–10am") in v1 — noted as a future extension.
- No web/Mac firing. Those platforms **store and display** location reminders but do **not** monitor regions (decided). Only the iPhone fires.
- No continuous background GPS tracking. We use OS region monitoring, which is cheap.

---

## 2. Two possible trigger mechanisms on iOS (pick one — recommendation below)

There are exactly two supported ways to do this on iOS. This matters because it drives the permission ask, the region limit, and battery.

### Option A — `UNLocationNotificationTrigger` (UserNotifications framework)
You hand a `CLRegion` to the notification center and it fires the notification when the region is entered/exited. Higher-level, less code.

- **Permission:** requires **When-In-Use at minimum**, but to fire reliably while the app is *not* running it effectively needs the OS to keep monitoring — in practice this path is **less reliable when the app is fully terminated** and Apple's guidance steers real geofencing toward `CLLocationManager`.
- **Pro:** almost no delegate code; reuses the existing `Notifications` scheduler.
- **Con:** fewer controls; you don't get the region-monitoring lifecycle callbacks; harder to debug "why didn't it fire."

### Option B — `CLLocationManager` region monitoring (Core Location) — **RECOMMENDED**
You register `CLCircularRegion`s with a `CLLocationManager`. The system wakes your app (even from terminated) on `didEnterRegion` / `didExitRegion`, and *you* post a local notification in that callback.

- **Permission:** to fire when the app is closed you need **Always** authorization. This is the honest requirement for "remind me when I arrive even though the app isn't open."
- **Pro:** this is the real, reliable geofencing path. Wakes from terminated. Full lifecycle callbacks for debugging. Same mechanism Apple Reminders uses.
- **Con:** more code (a `CLLocationManager` delegate object), and the **Always** permission is a bigger privacy ask + an App Store review justification.

**Recommendation: Option B.** The whole point is reliability when the app is closed. Option A's reliability caveat undermines the feature. We spec B as primary. (If review friction on "Always" ever becomes a blocker, A is the fallback, documented in §9.)

---

## 3. Permission model (decided: Always-on, explained)

Do **not** ask for "Always" cold on first launch — iOS shows it poorly and users decline. Use the correct two-step escalation:

1. **When the user first turns a reminder into a location reminder**, request **When-In-Use** (`requestWhenInUseAuthorization`). This is the gentle ask, tied to a clear in-context action.
2. **Then**, either immediately or on the next relevant moment, request the upgrade to **Always** (`requestAlwaysAuthorization`). iOS will later show the user a "keep allowing Always?" prompt on its own; that's expected.
3. If the user only grants When-In-Use, region monitoring still *works while the app is in use or recently backgrounded*, but we must **tell them plainly** it may not fire when the app is fully closed, and offer a one-tap deep link to Settings to upgrade.

**Required Info.plist keys (none exist yet — all new):**

| Key | Purpose | Example string |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | Step-1 ask | "Nudge uses your location to remind you when you arrive at or leave a place." |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Step-2 upgrade | "Allow Always so Nudge can remind you at a place even when the app is closed." |

**App Store review note:** the Always justification in App Store Connect must state the user-facing benefit ("location-based reminders that fire when the app is closed") and that we do not track or transmit location. **We do not send coordinates anywhere new** — geofencing is fully on-device; the coordinate already syncs to Supabase for display only. Worth stating this explicitly in the review notes to avoid rejection.

**Background mode:** region monitoring does **not** require the `location` background mode in most cases (the OS relaunches you for region events). We should verify on-device; do **not** add `UIBackgroundModes: location` unless testing proves it's needed, because it invites extra review scrutiny.

---

## 4. The iOS ~20-region hard limit (decided handling)

iOS lets a single app monitor a maximum of **20 regions** simultaneously (system-wide per app). Nudge could easily have more than 20 location reminders. Strategy:

- **Only monitor active, incomplete, location-triggered reminders** — completed/dismissed/snoozed-past ones don't count.
- If the count of eligible reminders **≤ 20**: monitor them all directly. Simple case, likely the common one for a personal app.
- If **> 20**: v1 **caps at the 20 nearest to the user's last known location** and shows a clear UI note: "Nudge can watch up to 20 places at once; the nearest 20 are active." Re-evaluate the active set opportunistically (on app foreground and on any region crossing). This is the same limit Apple Reminders lives under.
- **Future (not v1):** dynamic re-registration using `startMonitoringSignificantLocationChanges` to swap the monitored 20 as the user moves across the map. Documented as an extension, not built now.

State the cap in the UI honestly rather than silently dropping reminders.

---

## 5. Battery & reliability

- **Region monitoring is low-power.** It uses cell/Wi-Fi geofencing hardware, not continuous GPS. This is the cheap path — do **not** use `startUpdatingLocation` (that's the battery killer).
- **Minimum radius:** set region `radius` to at least ~100m (Apple recommends not going below the device's `maximumRegionMonitoringDistance` floor, typically ~100–150m). A too-small radius near a station causes missed or jittery triggers. Default radius: **150m**, not user-configurable in v1.
- **Debounce re-entry:** iOS already debounces, but we set `notifyOnEntry`/`notifyOnExit` per the reminder's chosen direction so we don't double-fire.
- **Cold-start latency:** region events can take a minute or two to fire after crossing — this is an OS characteristic, not a bug. UI copy should not promise "instant."

---

## 6. Data model changes

Add **three** fields to `struct Reminder` (and the mirrored web/Supabase shape). Keep them all optional/nullable so old clients and old rows are unaffected (matches the existing back-compat pattern in the model).

```swift
// New on struct Reminder (Models.swift). All optional for back-compat.
var geofenceEnabled: Bool? = nil   // true = this reminder fires on arrival/departure
var geofenceTrigger: String? = nil // "arrive" | "leave"   (nil treated as "arrive")
var geofenceRadius: Double? = nil  // metres; nil → default 150. Reserved for future UI.
```

- Reuse the **existing** `location`, `lat`, `lng` — do **not** add new coordinate fields.
- `geofenceEnabled == true` **requires** non-nil `lat`/`lng`. Enforce in the form (can't toggle geofence on without a picked location).
- A reminder may have **both** a due date and a geofence (e.g. "arrive at school" + a fallback time). **Resolved:** if both are set, **both** fire independently.

**Supabase:** add three nullable columns (`geofence_enabled boolean`, `geofence_trigger text`, `geofence_radius double precision`) to the reminders table. RLS already gates rows per authed user (recent D2 work) — these columns inherit that; **no** new policy needed. Migration is additive and non-destructive.

**Web (`index.html`):** read/write the three fields so the PWA round-trips them without data loss, and render the "fires on iPhone" label (see §8). Web never monitors.

---

## 7. iOS implementation sketch (grounded in existing files)

### 7.1 New file: `LocationMonitor.swift`
A single `@MainActor` object owning one `CLLocationManager`, kept alive for the app lifetime (Apple requires the manager to be a long-lived property, not a local).

```swift
import CoreLocation
import UserNotifications

@MainActor
final class LocationMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationMonitor()
    private let manager = CLLocationManager()
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false // we don't stream location
        authStatus = manager.authorizationStatus
    }

    // Step 1 of the permission escalation (§3)
    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    // Step 2 — call after When-In-Use is granted
    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// Rebuild the monitored set from the store. Call on: app foreground,
    /// reminder add/edit/complete, and after any region crossing.
    func sync(reminders: [Reminder], near: CLLocation?) {
        // 1. Stop monitoring regions that no longer qualify.
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        // 2. Eligible = geofenceEnabled == true, not completed/dismissed, has lat/lng.
        var eligible = reminders.filter {
            ($0.geofenceEnabled ?? false)
            && !($0.completed ?? false) && !($0.dismissed ?? false)
            && $0.lat != nil && $0.lng != nil
        }
        // 3. Enforce the 20-region cap (§4): nearest-first if we have a location.
        if eligible.count > 20, let here = near {
            eligible.sort { a, b in
                dist(a, here) < dist(b, here)
            }
            eligible = Array(eligible.prefix(20))
        } else {
            eligible = Array(eligible.prefix(20))
        }
        // 4. Register each.
        for r in eligible {
            let center = CLLocationCoordinate2D(latitude: r.lat!, longitude: r.lng!)
            let radius = min(r.geofenceRadius ?? 150,
                             manager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(center: center, radius: radius,
                                          identifier: r.id)          // id == reminder id
            region.notifyOnEntry = (r.geofenceTrigger ?? "arrive") == "arrive"
            region.notifyOnExit  = (r.geofenceTrigger ?? "arrive") == "leave"
            manager.startMonitoring(for: region)
        }
    }

    private func dist(_ r: Reminder, _ here: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: r.lat!, longitude: r.lng!).distance(from: here)
    }

    // MARK: CLLocationManagerDelegate
    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in await fire(regionId: region.identifier, kind: .arrive) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in await fire(regionId: region.identifier, kind: .leave) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in self.authStatus = m.authorizationStatus }
    }

    enum Kind { case arrive, leave }
    private func fire(regionId: String, kind: Kind) async {
        // Look up the reminder by id, build a UNMutableNotificationContent,
        // deliver with a nil trigger (fires immediately). Reuse existing
        // Notifications categories so tap-actions match the rest of the app.
    }
}
```

### 7.2 Hook points into existing code
- **`NudgeApp.swift`**: instantiate `LocationMonitor.shared` at launch (so it can be relaunched by the OS for region events) and call `sync(...)` on `.active` scene phase.
- **`Notifications.swift`**: the region-fired notification should reuse `registerCategories()` and the existing delegate so "Complete / Snooze" actions on a location notification behave identically to a time notification. Post it from `LocationMonitor.fire` via the same center. No change to `UNCalendarNotificationTrigger` paths.
- **`NudgeStore.swift`**: after any add/edit/complete of a reminder, call `LocationMonitor.shared.sync(...)`. Cheapest place to keep the monitored set fresh.

### 7.3 What NOT to touch
- Do not modify `LocationPickerView.swift`'s search behaviour — it stays permission-free for *search*. Permission is requested by the *form toggle*, not the picker.
- Do not add `startUpdatingLocation`.

---

## 8. UI — where the arrive/leave toggle lives

**Location:** in `AddReminderView.swift`, inside the existing Location section (where the picker is invoked). Flow:

1. User picks a place (existing picker). Once `lat`/`lng` are set, reveal a new **"Remind me when I…"** control directly beneath the place name:
   - A segmented control / toggle: **Arrive** ⇄ **Leave** (default Arrive).
   - A master switch "**Notify at this place**" that turns `geofenceEnabled` on/off. Off by default so existing "open in Maps" behaviour is unchanged for people who just want a bookmark.
2. **First time** the switch is turned on, trigger the permission escalation (§3). If denied, show inline: "Location access is off — this reminder won't fire at the place. [Open Settings]". Keep the reminder saveable regardless (it still syncs and shows on iPhone later).
3. **Web & Mac:** the same section renders the place and a **non-interactive label**: *"📍 Location reminder — fires on your iPhone."* Decided: web/Mac store the fields and show this label; they do not offer to monitor. (Mac *could* use Core Location later — noted in §9 — but v1 = label only, matching the decision.)

**Copy must be honest:** no "instant" promises; if only When-In-Use was granted, the label should say "may only fire while Nudge is open."

---

## 9. Platform parity summary (decided)

| Platform | Set location reminder | Monitors region / fires | Notes |
|---|---|---|---|
| **iPhone** | Yes | **Yes** (Core Location, Always) | The only firing platform in v1. |
| **iPad** | Yes | Yes, if it has the same target + location HW | Same code path as iPhone; low priority to verify. |
| **Mac** | Yes | **No** (store + label only) | macOS *has* Core Location region monitoring; deferred to a future version, not v1. |
| **Web (PWA)** | Yes | **No** (store + label only) | Browser geofencing is unreliable/unsupported for this; label only. |

Per project rule "always change web, iOS & Mac together": all three get the **schema + field round-trip + label** in the same change set. Only iOS gets the **monitoring engine**. That satisfies parity of *data* while being honest that only iPhone can fire.

---

## 10. Decisions (RESOLVED with Noah, 2026-07-10)

1. **Due date + geofence on the same reminder** — ✅ **RESOLVED: allow both** to fire independently. A reminder can have a time trigger and a place trigger; each fires on its own.
2. **>20 reminders behaviour** — ✅ **RESOLVED: "nearest 20" cap for v1.** Show the honest UI note. Dynamic significant-location-change swap deferred to a future version.
3. **Radius** — ✅ **RESOLVED: fixed 150m in v1.** No slider; `geofenceRadius` field stays reserved for a future release.
4. **Mac firing** — ✅ **RESOLVED: Mac is label-only in v1.** Core Location region monitoring on Mac is a fast-follow, not v1.
5. **When-In-Use fallback** — ✅ **RESOLVED: still monitor if only When-In-Use is granted**, with honest copy ("may only fire while Nudge is open"). Do not disable geofencing entirely; nudge the user toward Always via a Settings deep link.

All open decisions are now closed. Spec is build-ready pending Noah's go-ahead to start implementation.

---

## 11. Rough build order (once decisions are locked)

1. Schema: add 3 fields to `Reminder` (Swift) + 3 nullable Supabase columns + web read/write. Non-destructive, ship first.
2. UI: toggle + arrive/leave control in `AddReminderView`; label in web/Mac.
3. Permissions: Info.plist strings + two-step escalation in a small permissions helper.
4. Engine: `LocationMonitor.swift` + hooks in `NudgeApp` / `NudgeStore` / reuse `Notifications` categories.
5. Region cap + nearest-20 logic.
6. On-device test matrix: grant/deny paths, app-closed firing, arrive vs leave, >20 case, battery sanity.
7. Handoff MD + git commit, then a Claude Code push prompt (per project rules).

---

## 12. Security & safety notes (per project priority)

- **No new data leaves the device for geofencing.** Region matching is 100% on-device. The coordinate already syncs to Supabase (for display) under existing RLS — geofencing adds no new transmission.
- **No secrets/keys involved** in this feature. Nothing for Noah to paste anywhere.
- **Always-permission is the main privacy surface.** Mitigate with honest copy, in-context asks, and a truthful App Store review justification. Never request Always cold at launch.
- **Fail safe:** if permission is denied or monitoring fails, the reminder still exists and still shows — it simply doesn't fire at the place. No silent data loss.

---

*End of spec. Nothing built. Awaiting Noah's answers to §10 before any implementation.*
