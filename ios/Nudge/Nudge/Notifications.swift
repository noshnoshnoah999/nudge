// Notifications.swift — Nudge (iOS)
// Local reminder notifications. Schedules a notification for every open reminder
// with a future due date, offset by its `remindBefore` (minutes-before) field.
// Reschedules whenever data changes, on launch, and on foreground.

import Foundation
import UserNotifications
import SwiftUI
import Combine

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }
    @Published private(set) var authStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var scheduledCount: Int = 0

    private weak var nudge: NudgeStore?
    private var rescheduleTask: Task<Void, Never>?

    private enum Keys { static let enabled = "notificationsEnabled" }

    override init() {
        enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        super.init()
    }

    static let categoryId = "NUDGE_REMINDER"
    static let completeAction = "COMPLETE"
    static let snoozeAction = "SNOOZE"
    static let rescheduleAction = "RESCHEDULE"

    /// Shared instance — the app's @StateObject and the AppDelegate both use this one, so
    /// the notification delegate set at launch is the same object the UI talks to.
    static let shared = NotificationManager()

    /// Register the notification delegate + action categories. MUST run at app launch
    /// (from the AppDelegate), BEFORE any SwiftUI view appears — otherwise a Complete/
    /// Snooze tap that launches the app from a fully-quit state isn't delivered, and the
    /// default tap doesn't open the app. Idempotent.
    func registerForLaunch() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Actionable buttons on every reminder notification.
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "✓ Complete", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 1 hour", options: [])
        let rescheduleBtn = UNNotificationAction(identifier: Self.rescheduleAction, title: "Reschedule…", options: [.foreground])
        let cat = UNNotificationCategory(identifier: Self.categoryId, actions: [complete, snooze, rescheduleBtn],
                                         intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
    }

    func attach(_ store: NudgeStore) {
        nudge = store
        registerForLaunch()   // idempotent; the AppDelegate already did this at launch
        NotificationCenter.default.addObserver(forName: .nudgeDataChanged, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.scheduleDebounced() }
        }
        Task { await refreshAuthStatus(); await reschedule() }
    }

    // MARK: - Auth

    func refreshAuthStatus() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Remove already-DELIVERED notifications (sitting in Notification Centre) whose
    /// reminder is now completed / dismissed / gone — including its early-alert variants.
    /// Notifications are local to each device, so when a reminder is completed on the Mac,
    /// the iPhone must clear its own delivered copy on the next sync (rescheduling only
    /// drops PENDING ones). Cheap; safe to call often.
    func clearStaleDelivered() async {
        guard let nudge else { return }
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        var stale: [String] = []
        for n in delivered {
            let id = n.request.identifier
            guard id.hasPrefix("nudge-"), id != "nudge-payday" else { continue }
            let raw = String(id.dropFirst("nudge-".count))
            let rid = raw.contains("~") ? String(raw.split(separator: "~")[0]) : raw
            if let r = nudge.reminders.first(where: { $0.id == rid }) {
                if (r.completed ?? false) || (r.dismissed ?? false) { stale.append(id) }
            } else {
                stale.append(id)   // reminder no longer exists
            }
        }
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
    }

    /// Toggle on: ask the OS, then schedule. Returns to off if denied.
    func enable() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthStatus()
        guard granted else { enabled = false; return }
        enabled = true
        await reschedule()
    }

    func disable() {
        enabled = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        scheduledCount = 0
    }

    // MARK: - Scheduling

    private func scheduleDebounced() {
        guard enabled else { return }
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await self?.reschedule()
        }
    }

    /// Cancel all pending and reschedule for open, future, non-dismissed reminders.
    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        guard enabled, authStatus == .authorized || authStatus == .provisional, let nudge else {
            center.removeAllPendingNotificationRequests(); scheduledCount = 0; return
        }
        center.removeAllPendingNotificationRequests()

        let now = Date()
        // Each reminder yields a due-time alert plus one alert per early-reminder offset.
        var pending: [(r: Reminder, fire: Date, off: Int)] = []
        for r in nudge.reminders {
            if (r.completed ?? false) || (r.dismissed ?? false) { continue }
            if r.listIdOrDefault == "shopping" { continue }   // covered by the single pay-day summary
            guard let due = parseDate(r.dueDate) else { continue }
            // Due-time alert (respect a snooze that lands later).
            var mainFire = due
            if let s = parseDate(r.snoozedUntil), s > mainFire { mainFire = s }
            if mainFire > now { pending.append((r, mainFire, 0)) }
            // Early-reminder alerts (skipped once snoozed past their lead time).
            for off in r.earlyAlerts {
                let f = due.addingTimeInterval(-Double(off * 60))
                if f > now && parseDate(r.snoozedUntil) == nil { pending.append((r, f, off)) }
            }
        }
        pending.sort { $0.fire < $1.fire }

        // iOS allows at most 64 pending requests; keep the soonest.
        for p in pending.prefix(60) {
            let content = UNMutableNotificationContent()
            let prio = p.r.priorityOrNormal
            let high = prio == "high"
            let low = prio == "low"
            let shopping = p.r.listId == "shopping"
            let early = p.off > 0
            // Clean, Apple-Reminders-style layout: plain title, the list as subtitle, and the
            // notes (plus a heads-up line for early alerts) as the body. No emoji or filler —
            // priority is still conveyed by sound/interruption level, not the banner text.
            let title = displayTitle(p.r)
            content.title = title
            let listName = shopping ? "Shopping" : (nudge.list(for: p.r.listId)?.name ?? "")
            if !listName.isEmpty { content.subtitle = listName }
            var lines: [String] = []
            // iOS truncates the banner TITLE to one line — so a long reminder gets cut off.
            // Repeat the full title in the body (which wraps to several lines) so nothing is
            // lost. Short titles aren't repeated (the title already shows in full).
            if title.count > 30 { lines.append(title) }
            if early, let due = parseDate(p.r.dueDate) {
                let f = DateFormatter(); f.timeStyle = .short
                lines.append("In \(Self.leadLabel(p.off)) · due \(f.string(from: due))")
            }
            if let loc = p.r.location, !loc.isEmpty { lines.append(loc) }
            if let n = p.r.notes, !n.isEmpty { lines.append(n) }
            content.body = lines.joined(separator: "\n")
            // Low priority delivers quietly: no sound, lands in Notification Centre
            // without lighting up the screen. High is time-sensitive; normal is active.
            content.sound = low ? nil : .default
            content.interruptionLevel = high ? .timeSensitive : (low ? .passive : .active)
            content.categoryIdentifier = Self.categoryId
            content.threadIdentifier = "nudge-\(p.r.listId ?? "reminders")"   // groups by list
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let nid = p.off > 0 ? "nudge-\(p.r.id)~e\(p.off)" : "nudge-\(p.r.id)"
            let req = UNNotificationRequest(identifier: nid, content: content, trigger: trigger)
            try? await center.add(req)
        }
        await scheduleDigest(nudge: nudge, center: center)
        await schedulePayday(nudge: nudge, center: center)
        await scheduleBirthdays(center: center)
        await clearStaleDelivered()   // drop delivered alerts for now-completed reminders
        scheduledCount = min(pending.count, 60)
    }

    /// Heads-up notifications for upcoming birthdays (from the iOS Birthdays calendar): a
    /// reminder 3 days before at 09:00 and again on the morning of. Re-armed each reschedule.
    private func scheduleBirthdays(center: UNUserNotificationCenter) async {
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix("nudge-bday-") }
        if !existing.isEmpty { center.removePendingNotificationRequests(withIdentifiers: existing) }

        let cal = Calendar.current
        let bdays = CalendarService.shared.upcomingBirthdays(within: 30)
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
        for (i, b) in bdays.enumerated() {
            for lead in [3, 0] {
                guard let leadDay = cal.date(byAdding: .day, value: -lead, to: b.date),
                      let fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: leadDay),
                      fire > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = lead == 0 ? "🎂 \(b.title) — today!" : "🎂 \(b.title) in \(lead) days"
                content.body = lead == 0 ? "Don't forget to wish them 🎉" : "Coming up \(f.string(from: b.date))."
                content.sound = .default
                content.threadIdentifier = "nudge-birthdays"
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "nudge-bday-\(i)-\(lead)", content: content, trigger: trigger))
            }
        }
    }

    /// One pay-day summary instead of a notification per buy reminder: fires at the next
    /// payday 09:00 with how many things are waiting to be bought. Re-armed each
    /// reschedule (payday shifts off weekends, so it can't be a fixed repeating day).
    private func schedulePayday(nudge: NudgeStore, center: UNUserNotificationCenter) async {
        center.removePendingNotificationRequests(withIdentifiers: ["nudge-payday"])
        let pay = Payday.next()
        let n = nudge.buyReminders().filter {
            (parseDate($0.dueDate) ?? .distantFuture) <= Calendar.current.date(byAdding: .day, value: 1, to: pay)!
        }.count
        guard n > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "🛒 Pay day"
        content.body = "You have \(n) thing\(n == 1 ? "" : "s") to buy — tap to open your Shopping list."
        content.sound = .default
        content.threadIdentifier = "nudge-payday"
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: pay)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "nudge-payday", content: content, trigger: trigger))
    }

    /// A daily 9am digest of overdue + due-today counts. This is what makes
    /// notifications useful when most reminders are already overdue (those never
    /// fire their own alert). Refreshed each time reschedule() runs.
    private func scheduleDigest(nudge: NudgeStore, center: UNUserNotificationCenter) async {
        let cal = Calendar.current, now = Date()
        var overdue = 0, today = 0
        for r in nudge.reminders {
            if (r.completed ?? false) || (r.dismissed ?? false) { continue }
            guard let d = parseDate(r.dueDate) else { continue }
            if let s = parseDate(r.snoozedUntil), s > now { continue }
            if d < now { overdue += 1 } else if cal.isDateInToday(d) { today += 1 }
        }
        guard overdue > 0 || today > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Good Morning"
        var parts: [String] = []
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if today > 0 { parts.append("\(today) due today") }
        content.body = parts.joined(separator: " · ") + " — tap to triage"
        content.sound = .default
        content.threadIdentifier = "nudge-digest"
        var comps = DateComponents(); comps.hour = 9; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: "nudge-digest", content: content, trigger: trigger))
    }
}

// Show banners even when Nudge is in the foreground.
extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Handle the Complete / Snooze action buttons.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await handle(action: response.actionIdentifier,
                     notifId: response.notification.request.identifier)
    }

    /// "1 month" / "2 weeks" / "3 days" / "1 hour" / "45 min" for an early-alert lead time.
    static func leadLabel(_ m: Int) -> String {
        if m % 43200 == 0 { let n = m/43200; return "\(n) month\(n == 1 ? "" : "s")" }
        if m % 10080 == 0 { let n = m/10080; return "\(n) week\(n == 1 ? "" : "s")" }
        if m % 1440 == 0  { let n = m/1440;  return "\(n) day\(n == 1 ? "" : "s")" }
        if m % 60 == 0    { let n = m/60;    return "\(n) hour\(n == 1 ? "" : "s")" }
        return "\(m) min"
    }

    @MainActor private func handle(action: String, notifId: String) async {
        guard notifId.hasPrefix("nudge-") else { return }
        if notifId == "nudge-payday" { AppRouter.shared.pendingShopping = true; return }
        // Early-alert ids carry a "~e<minutes>" suffix — strip it to get the reminder id.
        let raw = String(notifId.dropFirst("nudge-".count))
        let rid = raw.contains("~") ? String(raw.split(separator: "~")[0]) : raw

        // A plain TAP (or Reschedule) launches the app to the FOREGROUND. If it was fully
        // quit, the live store/UI aren't up yet — and creating a throwaway NudgeStore here
        // (its load reloads widgets + mutates published state) during UIKit's launch & state-
        // restoration snapshot makes UIKit assert and abort. Hand it to the app to run live.
        let opensApp = action != Self.completeAction && action != Self.snoozeAction
        if nudge == nil && opensApp {
            AppRouter.shared.pendingNotification = NotifAction(action: action, rid: rid)
            return
        }
        // Complete/Snooze from fully-quit launch the app in the BACKGROUND (no scene snapshot),
        // so a throwaway store + persist is safe there. Pull latest cloud first so we don't
        // push a stale blob over newer edits.
        let store = nudge ?? NudgeStore()
        if action == Self.completeAction || action == Self.snoozeAction {
            await store.refresh()
        }
        guard let i = store.reminders.firstIndex(where: { $0.id == rid }) else { return }
        switch action {
        case Self.completeAction:
            store.toggleComplete(store.reminders[i])
            await store.persistNow()   // flush before iOS suspends us, else it's lost
        case Self.snoozeAction:
            // Same model as the card menu: push the due date out an hour. persist()
            // → reschedule() then re-arms the alert for the new time automatically.
            store.snooze(store.reminders[i], minutes: 60)
            await store.persistNow()
        case Self.rescheduleAction:
            AppRouter.shared.pendingReschedule = rid   // app opens → reschedule sheet
        default:
            // Tapping a "Claude - …" reminder's notification opens the app and
            // starts the Claude chat (so a Claude reminder set for later acts as
            // "ask Claude at this time"). Other reminders just open the app.
            if let p = ClaudeLink.prompt(from: store.reminders[i].title) {
                AppRouter.shared.pendingClaudePrompt = p
            }
        }
    }

}
