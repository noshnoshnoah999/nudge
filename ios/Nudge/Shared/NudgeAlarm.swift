// NudgeAlarm.swift — Nudge (shared between app + widget extension)
// The AlarmKit metadata for an "Urgent" reminder. Shared so both the app (which schedules
// the alarm) and the widget extension (which renders its Live Activity / Dynamic Island)
// agree on the exact type. AlarmKit is iOS 26+ and unavailable on Mac Catalyst, so the whole
// file is gated on canImport.

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
import CryptoKit
import Foundation

@available(iOS 26.0, *)
struct NudgeAlarmMetadata: AlarmMetadata {
    var title: String
    init(title: String) { self.title = title }
}

@available(iOS 26.0, *)
typealias NudgeAlarmAttributes = AlarmAttributes<NudgeAlarmMetadata>

/// Stable alarm UUID for a Nudge reminder id (which isn't itself a UUID). Shared so the app's
/// AlarmService (schedule/cancel) and the widget-completion path (cancel) derive the SAME id.
/// Moved here from AlarmService.alarmID on 2026-10-07 — the derivation is unchanged (MD5 of
/// the id's UTF-8 bytes), so alarms scheduled by older builds still cancel correctly.
nonisolated enum NudgeAlarmID {
    static func uuid(for reminderId: String) -> UUID {
        let d = Insecure.MD5.hash(data: Data(reminderId.utf8))
        var bytes = Array(d)
        return NSUUID(uuidBytes: &bytes) as UUID
    }
}
#endif
