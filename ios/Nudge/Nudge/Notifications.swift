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

    /// Register the action-button categories. Safe to run at process launch (AppDelegate) —
    /// it touches no scene/UI. Idempotent.
    func registerCategories() {
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "✓ Complete", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 1 hour", options: [])
        let rescheduleBtn = UNNotificationAction(identifier: Self.rescheduleAction, title: "Reschedule…", options: [.foreground])
        let cat = UNNotificationCategory(identifier: Self.categoryId, actions: [complete, snooze, rescheduleBtn],
                                         intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    /// Become the notification delegate. Do this only AFTER the SwiftUI scene exists (from
    /// `attach`, not the AppDelegate): if the delegate is set during didFinishLaunching, a
    /// tap that launched the app delivers its response into the half-built launch window and
    /// UIKit's state-restoration snapshot asserts → SIGABRT. Setting it post-scene means the
    /// queued launch response arrives when the window is valid. Idempotent.
    func registerForLaunch() {
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func attach(_ store: NudgeStore) {
        nudge = store
        registerForLaunch()   // sets the delegate now that the scene is up
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
            // Early-reminder alerts, suppressed only while a snooze is still pending.
            // snoozedUntil is never cleared once it passes, so testing it for mere
            // presence silenced a reminder's early alerts for good after one snooze.
            let snoozed = parseDate(r.snoozedUntil).map { $0 > now } ?? false
            for off in r.earlyAlerts {
                let f = due.addingTimeInterval(-Double(off * 60))
                if f > now && !snoozed { pending.append((r, f, off)) }
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
            // Title carries the full reminder text on its own (iOS may truncate a long title
            // to one line in the compact banner — accepted tradeoff). Body holds only
            // supplementary info, never a repeat of the title.
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

}

// Show banners even when Nudge is in the foreground.
extension NotificationManager: UNUserNotificationCenterDelegate {
    // Completion-handler variant, not `async`, for the SAME reason as didReceive below:
    // a `nonisolated async` @objc delegate method resumes on the cooperative thread pool,
    // so UIKit/UserNotifications runs the completion work off the main thread. This one is
    // not named in any crash report — the change is PRECAUTIONARY, because it is the identical
    // hazard and this method also awaits network I/O (`store.refresh()`), which is exactly
    // what forces the off-main resumption. Behaviour is otherwise unchanged.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                                @escaping (UNNotificationPresentationOptions) -> Void) {
        let show: UNNotificationPresentationOptions = [.banner, .sound, .list]
        // UNNotification is not Sendable — take the id now rather than capturing the object.
        let id = notification.request.identifier
        // Only reminder alerts are state-checked; payday / birthdays always show.
        guard id.hasPrefix("nudge-"), !id.hasPrefix("nudge-bday-"),
              id != "nudge-payday" else { completionHandler(show); return }
        let raw = String(id.dropFirst("nudge-".count))   // strip "~e<min>" early-alert suffix
        let rid = raw.contains("~") ? String(raw.split(separator: "~")[0]) : raw

        Task { @MainActor in
            // Pull the latest blob first: if this reminder was completed (or, for a daily repeat,
            // rolled to its next occurrence under a new id) on another device — the iPhone — the
            // Mac's own pending alert is now stale. Suppress it instead of banner-ing a thing you
            // already did. (Only helps while Nudge is foregrounded; a fully-asleep Mac can't run
            // this — that's the per-device local-notification limit.)
            let store = storeForPresentationCheck()
            await store?.refresh()
            let stale: Bool = {
                guard let store else { return false }
                guard let r = store.reminders.first(where: { $0.id == rid }) else { return true }
                return (r.completed ?? false) || (r.dismissed ?? false)
            }()
            completionHandler(stale ? [] : show)
        }
    }

    @MainActor private func storeForPresentationCheck() -> NudgeStore? { nudge }

    // Handle a notification tap and the Complete / Snooze / Reschedule action buttons.
    //
    // ⚠️ THIS MUST BE THE COMPLETION-HANDLER VARIANT, NOT THE `async` ONE. ⚠️
    //
    // It used to be `nonisolated func ... async`. Swift wraps an `async` @objc delegate method
    // in a thunk that invokes UIKit's completion handler when the async function RETURNS.
    // Because the method was `nonisolated`, that final resumption landed on the Swift
    // cooperative thread pool — so UIKit ran its completion work
    // (`-[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]`, which
    // refreshes the app-switcher snapshot) OFF the main thread and tripped an
    // NSAssertionHandler failure → SIGABRT, about a second after the app opened.
    //
    // Confirmed by five identical crash reports (2026-07-28 → 2026-08-03), every one with
    // faulting-thread queue `com.apple.root.user-initiated-qos.cooperative`:
    //
    //   -[NSAssertionHandler handleFailureInMethod:...]
    //   -[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]
    //   -[UIApplication _updateStateRestorationArchiveForBackgroundEvent:...updateSnapshot:...]
    //   -[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]
    //   @objc closure #1 in NotificationManager.userNotificationCenter(_:didReceive:)
    //   libswift_Concurrency  completeTaskWithClosure
    //
    // `handle()` being @MainActor did NOT prevent this: it hops to main correctly, but the
    // crash is on the way back OUT, when the nonisolated async function resumes.
    //
    // It only crashed on SOME notifications because a `handle()` call that returns without
    // ever suspending (a plain tap hitting an early `return`) completes inline on the main
    // thread. One that actually awaits — store.refresh(), persistNow(), any network I/O —
    // resumes on the pool and crashes. That is why Reschedule reproduced it reliably.
    //
    // The completion-handler variant fixes it outright: we own the Task, we pin it to
    // @MainActor, and we call `completionHandler()` there — so UIKit's snapshot work is
    // guaranteed to run on the main thread. Do not "simplify" this back to `async`.
    //
    // (This is also why AppDelegate's `shouldSaveSecureApplicationState = false` never
    // helped — UIKit still runs the `updateSnapshot:` half regardless of that opt-out.)
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        // Copy the two values we need off the response now — UNNotificationResponse is not
        // Sendable, so it must not be captured by the Task.
        let action = response.actionIdentifier
        let notifId = response.notification.request.identifier
        Task { @MainActor in
            await handle(action: action, notifId: notifId)
            completionHandler()
        }
    }

    /// "1 month" / "2 weeks" / "3 days" / "1 hour" / "45 min" for an early-alert lead time.
    static func leadLabel(_ m: Int) -> String {
        if m % 43200 == 0 { let n = m/43200; return "\(n) month\(n == 1 ? "" : "s")" }
        if m % 10080 == 0 { let n = m/10080; return "\(n) week\(n == 1 ? "" : "s")" }
        if m % 1440 == 0  { let n = m/1440;  return "\(n) day\(n == 1 ? "" : "s")" }
        if m % 60 == 0    { let n = m/60;    return "\(n) hour\(n == 1 ? "" : "s")" }
        return "\(m) min"
    }

    /// A notification tap recorded during a fully-quit launch, before any UI exists. Held in
    /// a PLAIN (non-@Published) static so recording it touches no observed state — see handle().
    nonisolated(unsafe) static var pendingColdTap: (action: String, notifId: String)?

    @MainActor private func handle(action: String, notifId: String) async {
        guard notifId.hasPrefix("nudge-") else { return }
        let opensApp = action != Self.completeAction && action != Self.snoozeAction

        // COLD-LAUNCH foreground-opening tap (plain tap / Reschedule / pay-day): the live store
        // + UI aren't up yet, so there is nothing to drive. Stash the tap in a plain holder and
        // let the app consume it once live (ContentView.processPendingNotification).
        //
        // This branch is REQUIRED, and not for the reason originally written here. The old note
        // claimed touching @Published state during launch commits a CATransaction inside UIKit's
        // restoration window and asserts. That diagnosis was wrong — the real cause of the crash
        // was this delegate method being `nonisolated async`, so its completion handler ran off
        // the main thread (see the long comment on the delegate method above). The branch stays
        // because at this point `nudge` genuinely is nil: NotificationManager.attach() runs from
        // SwiftUI's .task, after didFinishLaunching, so on a cold launch there is no store yet.
        if nudge == nil && opensApp {
            Self.pendingColdTap = (action, notifId)
            return
        }

        // Warm (app already live) — or a background Complete/Snooze, or (for Urgent reminders)
        // an app that AlarmKit woke in the background to manage its alarm.
        //
        // `onMain` defers each observed-state write one runloop tick. Its original justification
        // (avoiding a CATransaction commit inside UIKit's restoration window) was part of the
        // same wrong diagnosis, so this is very probably redundant now that the delegate's
        // completion handler is correctly main-actor pinned. It is kept because it costs one
        // tick, is provably harmless, and the crash it was written for took five attempts and
        // five crash reports to pin down — removing it buys nothing and reopens a settled
        // question. If it ever does get removed, re-run the full notification test matrix.
        func onMain(_ work: @escaping @MainActor () -> Void) { DispatchQueue.main.async { work() } }
        if notifId == "nudge-payday" { onMain { AppRouter.shared.pendingShopping = true }; return }
        let raw = String(notifId.dropFirst("nudge-".count))   // strip "~e<min>" early-alert suffix
        let rid = raw.contains("~") ? String(raw.split(separator: "~")[0]) : raw
        let store = nudge ?? NudgeStore()
        if action == Self.completeAction || action == Self.snoozeAction { await store.refresh() }
        guard let i = store.reminders.firstIndex(where: { $0.id == rid }) else { return }
        switch action {
        case Self.completeAction:
            store.toggleComplete(store.reminders[i]); await store.persistNow()
        case Self.snoozeAction:
            store.snooze(store.reminders[i], minutes: 60); await store.persistNow()
        case Self.rescheduleAction:
            onMain { AppRouter.shared.pendingReschedule = rid }
        default:
            // Open the specific reminder the user tapped (Claude reminders start their chat).
            if let p = ClaudeLink.prompt(from: store.reminders[i].title) {
                onMain { AppRouter.shared.pendingClaudePrompt = p }
            } else {
                onMain { AppRouter.shared.pendingOpenReminder = rid }
            }
        }
    }

}
