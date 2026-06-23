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
    static func schedule(reminderId: String, title: String, at date: Date) async {
        guard date > Date(), await authorize() else { return }
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
        _ = try? await AlarmManager.shared.schedule(id: alarmID(reminderId), configuration: config)
    }

    /// Cancel a reminder's alarm (when it's completed, deleted, un-urgented, or moved).
    static func cancel(reminderId: String) {
        try? AlarmManager.shared.cancel(id: alarmID(reminderId))
    }

    /// Stable UUID for a Nudge reminder id (which isn't itself a UUID) so schedule + cancel
    /// target the same alarm.
    private static func alarmID(_ reminderId: String) -> UUID {
        let d = Insecure.MD5.hash(data: Data(reminderId.utf8))
        var bytes = Array(d)
        return NSUUID(uuidBytes: &bytes) as UUID
    }
}
#endif
