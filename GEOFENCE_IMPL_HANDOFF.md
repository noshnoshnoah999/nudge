# Geofencing — Implementation Handoff

**Date:** 2026-07-10
**Status:** Built, both targets compile clean. **Needs Noah's on-device walk test** (see §3).
**Spec:** `GEOFENCE_SPEC.md` — all §10 decisions honoured. Deviations in §2.

---

## 1. What was built

| File | Change |
|---|---|
| `Models.swift` | +3 optional fields on `Reminder`: `geofenceEnabled`, `geofenceTrigger`, `geofenceRadius`. Synthesized `CodingKeys` (no explicit enum) → old blobs decode fine, no schema change. |
| `LocationMonitor.swift` | **New.** `@MainActor` singleton owning one `CLLocationManager`. Region monitoring, 20-region nearest-first cap, two-step permission escalation, fires the local notification. |
| `NudgeApp.swift` | Builds `LocationMonitor.shared` in `AppDelegate.didFinishLaunching`; re-syncs regions on scene `.active`. |
| `NudgeStore.swift` | `sync(...)` at the `persist()` choke point (one call, covers add/edit/complete/dismiss). `saveReminder` + `saveReminderThisOccurrenceOnly` carry the two new fields. |
| `AddReminderView.swift` | "Notify at this place" toggle + Arrive⇄Leave segmented control, revealed once `lat`/`lng` are set. Permission escalation, honest copy, Open Settings link, 20-region note. |
| `Info.plist` | `NSLocationWhenInUseUsageDescription`, `NSLocationAlwaysAndWhenInUseUsageDescription`. |

`index.html` untouched (web is retired). No `startUpdatingLocation`. No `UIBackgroundModes: location`. No SQL migration. No secrets involved.

---

## 2. Deviations from the prompt — and why

**1. Mac gating is `#if targetEnvironment(macCatalyst)`, not `#if os(macOS)`.**
The prompt (TASK 5) said `#if os(macOS)`. **That would have been a real bug.** The Mac app is Mac Catalyst (`SUPPORTS_MACCATALYST = YES`; there is not one `os(macOS)` in the codebase), and under Catalyst `os(macOS)` is **false** while `os(iOS)` is **true**. Using it would have shown the Mac the full iOS toggle *and had it request location permission* — the exact opposite of the locked decision. Mac now shows the label only and asks for nothing.

**2. `LocationMonitor.shared` is built in `AppDelegate.didFinishLaunching`, not only in `NudgeApp`'s `.task`.**
The OS relaunches the app straight into a region event **with no scene**, so a `.task` never runs — `NudgeApp.swift`'s own comment already documents this exact trap for the notification delegate. A `CLLocationManager` only delivers to a delegate that exists at launch, so the `.task`-only wiring in the prompt would have silently dropped app-closed firings — i.e. the whole feature. The `.task`/`.active` sync call is still there for the foreground refresh.

**3. Location notification id is `nudge-<id>~geo`, not `nudge-<id>`.**
`UNUserNotificationCenter.add` **replaces** any request with the same identifier, so reusing the bare `nudge-<id>` would have cancelled that reminder's *pending timed* notification — breaking locked decision #7 (both triggers fire independently). The `~geo` suffix is stripped by the delegate's existing `raw.split(separator: "~")[0]` parser, so Complete/Snooze/Reschedule resolve to the right reminder and `clearStaleDelivered()` still cleans it up. Verified against the real parsing expressions.

**4. Cold-relaunch lookup uses a `UserDefaults` snapshot, not `NudgeStore`.**
The spec left `fire(...)` a stub. On an OS relaunch there is no store built, and constructing one is async/networked. Each `sync()` mirrors `{id: title, place}` for the monitored set into `UserDefaults`, so `fire` is a pure local read — no store, no network, no cold-launch race.

**5. `near:` defaults to Core Location's free cached `manager.location`.**
The prompt said pass `nil` if no cheap last-known position exists. `manager.location` *is* that cheap value (a cached read, starts nothing), so the nearest-20 cap works without a location request. Falls back to arbitrary `prefix(20)` when it's nil.

**6. `saveReminder` signature gained `geofenceEnabled`/`geofenceTrigger`;** removing a place now also clears the geofence (a trigger without a coordinate is meaningless). `geofenceRadius` is written nowhere — reserved, fixed 150m, per decision #6.

**7. Added `import Combine`** to `LocationMonitor.swift` (required for `@Published`; build error without it).

---

## 3. Test status — read this before trusting the feature

**Verified by me:**
- `xcodebuild` clean for **iOS Simulator** and **Mac Catalyst**.
- Notification-id round-trip: `nudge-r123~geo` → `r123` under the delegate's actual parser (and `~e60` early alerts still parse, `nudge-payday` still ignored).
- Mac Catalyst: toggle + permission calls compile out entirely; label-only path.

**NOT verified — needs a real iPhone, these are the ones that matter:**
- [ ] **App-closed firing.** Walk in/out of a real 150m region with Nudge fully quit. This is the whole feature and the only way to prove #2 above actually works.
- [ ] Grant path: toggle on → When-In-Use prompt → Always prompt, in that order.
- [ ] Deny path: reminder still saves; inline copy + Open Settings appear.
- [ ] Arrive vs Leave map to the right `notifyOnEntry`/`notifyOnExit`.
- [ ] >20 eligible reminders → only 20 monitored, nearest-first, UI note shows. (Cap logic is unit-untested.)
- [ ] Complete/Snooze buttons on a *location* notification.

Region events can lag a minute or two after crossing — that's normal OS behaviour, not a bug. Simulator: Features ▸ Location ▸ Custom Location can fake a crossing for the grant/arrive paths, but not a true terminated-app relaunch.

---

## 4. Safety

Geofencing is 100% on-device; no new data leaves the phone. The coordinate already synced for display under existing RLS. The only privacy surface is the Always permission — requested in-context on first toggle, never cold at launch, with copy that promises nothing it can't keep ("May only fire while Nudge is open." when only When-In-Use is granted). Fail-safe: if permission is denied or monitoring fails, the reminder still saves, syncs and displays — it just won't fire at the place. No silent data loss.

**App Store review note (if ever submitted):** justify Always as "location-based reminders that fire when the app is closed", and state that location is never tracked or transmitted.
