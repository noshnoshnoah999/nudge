// AlarmService.swift — Nudge (iOS)
// Schedules a real system alarm (AlarmKit) for reminders marked "Urgent" — it rings and
// shows a Live Activity / Dynamic Island at the due time even when the app is closed, like
// Apple Reminders' urgent reminders. iOS 26+ only; excluded from Mac Catalyst via canImport.

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
import ActivityKit
import SwiftUI
import CryptoKit

@available(iOS 26.0, *)
enum NudgeAlarms {
    /// Ask for AlarmKit permission once. Returns whether we're authorized.
    @discardableResult
    static func authorize() async -> Bool {
        let mgr = AlarmManager.shared
        if mgr.authorizationState == .authorized { return true }
        return (try? await mgr.requestAuthorization()) == .authorized
    }

    /// How long "Snooze" delays the alarm before it rings again (Apple's default is 9 min).
    static let snoozeDuration: TimeInterval = 9 * 60

    /// Schedule (or replace) an urgent reminder's alarm for its due time. No-op if the time
    /// is in the past or permission is denied. Presents an Apple-Reminders-style alarm: a big
    /// "Snooze" button + slide-to-stop, and a "Snooze 8:57 min" countdown Live Activity.
    /// Returns true when AlarmKit accepted the alarm.
    @discardableResult
    static func schedule(reminderId: String, title: String, at date: Date) async -> Bool {
        guard date > Date(), await authorize() else { return false }
        let text = LocalizedStringResource(stringLiteral: title.isEmpty ? "Reminder" : title)
        // Alert: system provides slide-to-stop; we add a Snooze secondary button that drops the
        // alarm into a countdown (the snooze) and re-rings.
        let alert = AlarmPresentation.Alert(
            title: text,
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown)
        // Countdown: shown while snoozed.
        let countdown = AlarmPresentation.Countdown(title: text, pauseButton: nil)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: nil),
            metadata: NudgeAlarmMetadata(title: title),
            tintColor: Color.orange)
        let config = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeDuration),
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default)
        do {
            _ = try await AlarmManager.shared.schedule(id: alarmID(reminderId), configuration: config)
            return true
        } catch {
            return false
        }
    }

    /// Cancel a reminder's alarm (when it's completed, deleted, un-urgented, or moved).
    static func cancel(reminderId: String) {
        try? AlarmManager.shared.cancel(id: alarmID(reminderId))
    }

    /// Stable UUID for a Nudge reminder id (which isn't itself a UUID) so schedule + cancel
    /// target the same alarm.
    private static func alarmID(_ reminderId: String) -> UUID {
        NudgeAlarmID.uuid(for: reminderId)   // Shared/NudgeAlarm.swift — one derivation for app + widget path
    }
}

/// Keeps every urgent reminder's alarm matched to the reminder's CURRENT time (2026-11-06).
/// Before this, only the edit sheet armed/moved alarms, so a reminder moved by Reschedule,
/// bulk move, Smart Reschedule, Move Over, undo, a snooze, or an edit synced from the Mac
/// (no AlarmKit there) still rang at the OLD time — and a repeating urgent reminder's next
/// occurrence never got an alarm at all.
///
/// Runs from NotificationManager on every data change, launch, foreground and sync — whether
/// or not notifications are switched on (alarms are a separate permission).
/// A ledger (reminderId → "epochSeconds|title" we last armed) means only real changes touch
/// AlarmKit. Rules:
///  • open, urgent, TIMED, time (due, or a later snooze) in the future → alarm at that time
///  • alarm whose time has arrived and the reminder hasn't moved → left alone (it is ringing,
///    in its 9-min snooze countdown, or already stopped)
///  • anything else in the ledger (completed, deleted, dismissed, un-urgented, moved into the
///    past, completed from the widget but not yet synced) → cancelled
@available(iOS 26.0, *)
@MainActor
enum NudgeAlarmReconciler {
    private static let ledgerKey = "urgentAlarmLedger"
    private static var running = false
    private static var again = false

    static func reconcile(_ snapshot: @escaping @MainActor () -> [Reminder]) async {
        if running { again = true; return }   // a run is mid-flight: it will loop once more
        running = true
        defer { running = false }
        repeat {
            again = false
            await runOnce(snapshot())
        } while again
    }

    private static func runOnce(_ reminders: [Reminder]) async {
        // An empty list at launch means "not loaded yet", not "everything deleted" — never
        // cancel every alarm on that basis.
        guard !reminders.isEmpty else { return }
        var ledger = (UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String]) ?? [:]
        let now = Date()
        var byId: [String: Reminder] = [:]
        for r in reminders { byId[r.id] = r }

        func fireTime(_ r: Reminder) -> Date? {
            guard let due = parseDate(r.dueDate) else { return nil }
            if let s = parseDate(r.snoozedUntil), s > due { return s }   // snooze → ring again then
            return due
        }
        func isLive(_ r: Reminder) -> Bool {
            // Timed reminders only (a date-only one would ring at midnight) — same rule as before.
            (r.urgent ?? false) && (r.hasTime ?? false) && !(r.completed ?? false) && !(r.dismissed ?? false)
                && !WidgetCompletionLedger.isCompleted(id: r.id, due: r.dueDate)
        }
        func entry(_ fire: Date, _ title: String) -> String { "\(Int(fire.timeIntervalSince1970))|\(title)" }
        func armedTime(_ e: String) -> Double? { e.split(separator: "|", maxSplits: 1).first.flatMap { Double($0) } }

        // 1. Arm or move alarms for live urgent reminders with a future time.
        for r in reminders where isLive(r) {
            guard let fire = fireTime(r), fire > now else { continue }
            let want = entry(fire, r.title)
            if ledger[r.id] == want { continue }            // already armed for this time + title
            NudgeAlarms.cancel(reminderId: r.id)           // replace cleanly, never stack
            if await NudgeAlarms.schedule(reminderId: r.id, title: r.title, at: fire) {
                ledger[r.id] = want
            } else {
                ledger.removeValue(forKey: r.id)           // denied / failed: retry next pass
            }
        }

        // 2. Cancel alarms that should no longer ring.
        for (id, e) in ledger {
            if let r = byId[id], isLive(r), let fire = fireTime(r) {
                if fire > now { continue }                 // handled in step 1
                if let t = armedTime(e), abs(t - fire.timeIntervalSince1970) < 60 { continue }   // ringing / snoozing / done
            }
            NudgeAlarms.cancel(reminderId: id)
            ledger.removeValue(forKey: id)
        }
        UserDefaults.standard.set(ledger, forKey: ledgerKey)
    }
}
#endif
