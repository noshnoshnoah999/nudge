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
    static let testNowID = "tsuji-test-now"
    static let maxPending = 64
    static let daysAhead = 7

    static func schedule(center: UNUserNotificationCenter = .current()) async {
        // Until the first calendar read, TsujiStore has no items; scheduling now would only
        // remove everything. NotificationManager.reschedule() at launch runs before that.
        guard TsujiStore.shared.hasLoaded else { return }

        let pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
        let ours = pendingIDs.filter { $0.hasPrefix(prefix) && $0 != testNowID }
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
            .filter { $0.hasPrefix(prefix) && $0 != testNowID }
        guard !delivered.isEmpty else { return }
        let openPrefixes = TsujiStore.shared.items
            .filter { $0.isOpen && !$0.isTestEntry }
            .map { "\(prefix)\(TsujiStore.shortID($0.id))-" }
        let stale = delivered.filter { id in !openPrefixes.contains(where: { id.hasPrefix($0) }) }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    // MARK: - Test mode helpers

    struct PendingInfo: Identifiable {
        let id: String
        let title: String
        let when: String
    }

    /// The Tsuji notifications currently waiting to fire on this device, soonest first.
    static func pendingInfo() async -> [PendingInfo] {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        var rows: [(Date, PendingInfo)] = []
        for r in requests where r.identifier.hasPrefix(prefix) {
            let next = (r.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                ?? (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                ?? .distantFuture
            rows.append((next, PendingInfo(id: r.identifier, title: r.content.title, when: f.string(from: next))))
        }
        return rows.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// Fire one sample Tsuji notification in 5 seconds, to check how it looks.
    static func sendTestNow() async -> String {
        let mgr = NotificationManager.shared
        guard mgr.enabled, mgr.authStatus == .authorized || mgr.authStatus == .provisional else {
            return "Nudge notifications are off. Turn them on in Nudge's Settings first."
        }
        let first = TsujiStore.shared.nowItems.first { !$0.isTestEntry }
        let content = UNMutableNotificationContent()
        let when = first.map { TsujiFormat.relative($0.status) } ?? "due today"
        content.title = "[TEST] Tsuji: \(first?.title ?? "Example item") — \(when)"
        content.body = "Sample notification from Test mode."
        content.sound = .default
        content.threadIdentifier = "tsuji-plan"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        do {
            try await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: testNowID, content: content, trigger: trigger))
            return "Sent. It should appear in about 5 seconds."
        } catch {
            return "Couldn't schedule it: \(error.localizedDescription)"
        }
    }
}
