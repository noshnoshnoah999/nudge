// TsujiNotifications.swift — Nudge (iOS + Mac Catalyst)
// Tsuji Action Banner, step 2 — local notifications (spec section 8 + Noah's decisions).
//
//  • Each open item: 09:00 local on the due date, then every day at 09:00 until cleared,
//    scheduled 7 days ahead and topped up on every launch / foreground / calendar change.
//  • Both iPhone and Mac schedule their own (Noah accepts duplicates, 29 Oct 2026).
//  • Nudge keeps at most 64 pending notifications. Tsuji only uses what is LEFT after normal
//    reminders, pay day and birthdays, and drops its furthest-out days first (Noah, 1 Nov 2026).
//  • Identifiers start with "tsuji-", NOT "nudge-": NotificationManager's tap handler, its
//    foreground check and clearStaleDelivered() all ignore ids that don't start with "nudge-",
//    so Tsuji alerts are never treated as reminders and have no Complete/Snooze actions.
//    The only way to clear an item stays the typed phrase.
//
// NotificationManager.reschedule() removes ALL pending requests and then calls schedule() at
// its end; TsujiStore also calls schedule() after every reload.

import Foundation
import UserNotifications

@MainActor
enum TsujiNotifications {
    static let prefix = "tsuji-"
    static let maxPending = 64
    static let daysAhead = 7

    static func schedule(center: UNUserNotificationCenter = .current()) async {
        // Until the first calendar read, TsujiStore has no items; scheduling now would only
        // remove everything. NotificationManager.reschedule() at launch runs before that.
        guard TsujiStore.shared.hasLoaded else { return }

        let pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
        let ours = pendingIDs.filter { $0.hasPrefix(prefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }
        await removeDeliveredForClosedItems(center: center)

        // Respect Nudge's own Notifications switch and the system permission.
        let mgr = NotificationManager.shared
        guard mgr.enabled, mgr.authStatus == .authorized || mgr.authStatus == .provisional else { return }

        let budget = max(0, maxPending - (pendingIDs.count - ours.count))
        for p in TsujiStore.shared.notificationPlan(daysAhead: daysAhead).prefix(budget) {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            content.interruptionLevel = .active
            content.threadIdentifier = "tsuji-plan"
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
        }
    }

    /// Remove delivered Tsuji alerts (in Notification Centre) for items that are no longer open.
    private static func removeDeliveredForClosedItems(center: UNUserNotificationCenter) async {
        let delivered = await center.deliveredNotifications()
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(prefix) }
        guard !delivered.isEmpty else { return }
        let openPrefixes = TsujiStore.shared.items
            .filter { $0.isOpen }
            .map { "\(prefix)\(TsujiStore.shortID($0.id))-" }
        let stale = delivered.filter { id in !openPrefixes.contains(where: { id.hasPrefix($0) }) }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }
}
