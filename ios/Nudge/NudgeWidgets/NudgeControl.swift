// NudgeControl.swift — Nudge widget extension
// A Control Center control: one tap opens Nudge straight into quick-add.

import WidgetKit
import SwiftUI
import AppIntents

#if !targetEnvironment(macCatalyst)   // Control Centre controls are iOS-only
struct NudgeQuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "uk.flouty.Nudge.quickadd") {
            ControlWidgetButton(action: QuickAddReminderIntent()) {
                Label("Add Reminder", systemImage: "bell.badge.fill")
            }
        }
        .displayName("Add to Nudge")
        .description("Quickly add a reminder to Nudge.")
    }
}
#endif
