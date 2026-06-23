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

    /// Schedule (or replace) an urgent reminder's alarm for its due time. No-op if the time
    /// is in the past or permission is denied.
    static func schedule(reminderId: String, title: String, at date: Date) async {
        guard date > Date(), await authorize() else { return }
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title.isEmpty ? "Reminder" : title),
            secondaryButton: nil,
            secondaryButtonBehavior: nil)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
            metadata: NudgeAlarmMetadata(title: title),
            tintColor: Color.orange)
        let config = AlarmManager.AlarmConfiguration.alarm(
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
