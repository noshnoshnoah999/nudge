// NudgeAlarm.swift — Nudge (shared between app + widget extension)
// The AlarmKit metadata for an "Urgent" reminder. Shared so both the app (which schedules
// the alarm) and the widget extension (which renders its Live Activity / Dynamic Island)
// agree on the exact type. AlarmKit is iOS 26+ and unavailable on Mac Catalyst, so the whole
// file is gated on canImport.

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit

@available(iOS 26.0, *)
struct NudgeAlarmMetadata: AlarmMetadata {
    var title: String
    init(title: String) { self.title = title }
}

@available(iOS 26.0, *)
typealias NudgeAlarmAttributes = AlarmAttributes<NudgeAlarmMetadata>
#endif
