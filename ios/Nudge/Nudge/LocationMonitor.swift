import Foundation
import Combine
import CoreLocation
import UserNotifications

/// Location-triggered reminders ("remind me when I arrive at / leave X").
///
/// Uses Core Location **region monitoring** — the OS wakes (or relaunches) the app on a
/// boundary crossing and we post a local notification from the delegate callback. This is the
/// cheap, low-power path: we never call `startUpdatingLocation` and never stream a position.
/// Region matching is 100% on-device; geofencing sends nothing new anywhere.
///
/// iPhone/iPad only. Mac (Catalyst) has no region monitoring, so the guts compile out there and
/// every method becomes a no-op — call sites stay free of `#if`.
@MainActor
final class LocationMonitor: NSObject, ObservableObject {
    static let shared = LocationMonitor()

    /// iOS monitors at most 20 regions per app, system-wide. See `sync(reminders:near:)`.
    static let maxRegions = 20
    /// Fixed in v1. `Reminder.geofenceRadius` is reserved for a future slider.
    static let defaultRadius: CLLocationDistance = 150

    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    /// True when more reminders wanted a geofence than iOS will let us watch, so the UI can
    /// say so honestly rather than silently dropping the rest.
    @Published private(set) var capped = false

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = false  // we never stream location
        authStatus = manager.authorizationStatus
    }

    // MARK: - Permission (two-step escalation — never ask for Always cold at launch)

    /// Step 1: the gentle ask, made in-context when the user first turns a geofence on.
    func requestWhenInUse() {
        #if !targetEnvironment(macCatalyst)
        manager.requestWhenInUseAuthorization()
        #endif
    }

    /// Step 2: upgrade to Always, so a reminder can fire with the app fully closed.
    func requestAlways() {
        #if !targetEnvironment(macCatalyst)
        manager.requestAlwaysAuthorization()
        #endif
    }

    /// Geofences can still fire with only When-In-Use, but only while Nudge is open/recently
    /// backgrounded. The UI uses this to show honest copy instead of promising a background fire.
    var canFireWhenClosed: Bool { authStatus == .authorizedAlways }
    var isDenied: Bool { authStatus == .denied || authStatus == .restricted }

    // MARK: - Monitored set

    /// Rebuild the monitored regions from the store. Cheap and idempotent — call on app
    /// foreground and at the persist choke point after any reminder add/edit/complete.
    ///
    /// `near` is the yardstick for the 20-region cap: when more reminders are eligible than iOS
    /// will watch, we keep the ones nearest to it. Falls back to Core Location's free cached
    /// last-known position (no location request is started for this).
    func sync(reminders: [Reminder], near: CLLocation? = nil) {
        #if !targetEnvironment(macCatalyst)
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }

        var eligible = reminders.filter {
            ($0.geofenceEnabled ?? false)
                && !($0.completed ?? false) && !($0.dismissed ?? false)
                && $0.lat != nil && $0.lng != nil
        }
        capped = eligible.count > Self.maxRegions

        // Nearest-first when we know roughly where we are; otherwise take an arbitrary 20.
        if capped, let here = near ?? manager.location {
            eligible.sort { distance(from: $0, to: here) < distance(from: $1, to: here) }
        }
        eligible = Array(eligible.prefix(Self.maxRegions))

        for r in eligible {
            guard let lat = r.lat, let lng = r.lng else { continue }
            let radius = min(r.geofenceRadius ?? Self.defaultRadius,
                             manager.maximumRegionMonitoringDistance)
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                radius: radius,
                identifier: r.id)                       // identifier == reminder id
            let arriving = (r.geofenceTrigger ?? "arrive") == "arrive"
            region.notifyOnEntry = arriving
            region.notifyOnExit = !arriving
            manager.startMonitoring(for: region)
        }

        saveSnapshot(of: eligible)
        #endif
    }

    private func distance(from r: Reminder, to here: CLLocation) -> CLLocationDistance {
        guard let lat = r.lat, let lng = r.lng else { return .greatestFiniteMagnitude }
        return CLLocation(latitude: lat, longitude: lng).distance(from: here)
    }

    // MARK: - Firing

    /// The OS can relaunch us straight into a region event with no `NudgeStore` built yet, so the
    /// title/place of every monitored reminder is mirrored into UserDefaults at sync time. That
    /// makes `fire` a pure local read — no store, no network, no race on a cold launch.
    private static let snapshotKey = "geofenceSnapshot"

    private func saveSnapshot(of reminders: [Reminder]) {
        let snap = reminders.reduce(into: [String: [String: String]]()) { acc, r in
            acc[r.id] = ["title": r.title, "place": r.location ?? ""]
        }
        UserDefaults.standard.set(snap, forKey: Self.snapshotKey)
    }

    private func snapshot(for id: String) -> (title: String, place: String)? {
        let all = UserDefaults.standard.dictionary(forKey: Self.snapshotKey) as? [String: [String: String]]
        guard let e = all?[id], let title = e["title"] else { return nil }
        return (title, e["place"] ?? "")
    }

    fileprivate func fire(regionId: String, arriving: Bool) {
        guard let (title, place) = snapshot(for: regionId) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        let where_ = place.isEmpty ? "this place" : place
        content.body = arriving ? "You've arrived at \(where_)" : "You've left \(where_)"
        content.sound = .default
        // Same category as timed reminders → identical Complete / Snooze / Reschedule buttons.
        content.categoryIdentifier = NotificationManager.categoryId

        // `nudge-<id>` is what the notification delegate parses back into a reminder id (it
        // strips any `~suffix`). The `~geo` suffix keeps this request distinct from the pending
        // timed one — reusing the bare id would REPLACE it and silently cancel the time alert.
        let request = UNNotificationRequest(identifier: "nudge-\(regionId)~geo",
                                            content: content,
                                            trigger: nil)   // nil → deliver now
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationMonitor: CLLocationManagerDelegate {
    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in self.fire(regionId: region.identifier, arriving: true) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in self.fire(regionId: region.identifier, arriving: false) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let status = m.authorizationStatus
        Task { @MainActor in self.authStatus = status }
    }
}
