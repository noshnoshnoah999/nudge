// NudgeControl.swift — Nudge widget extension
// A Control Center control: one tap opens Nudge straight into quick-add.

import WidgetKit
import SwiftUI
import AppIntents

#if !targetEnvironment(macCatalyst)   // Control Centre controls are iOS-only
struct NudgeQuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "uk.flouty.Nudge.quickadd") {
            ControlWidgetButton(action: QuickCatchIntent()) {
                Label("Catch a Thought", systemImage: "bolt.badge.clock.fill")
            }
        }
        .displayName("Catch a Thought")
        .description("Jot a thought; Nudge picks a smart time for it.")
    }
}
#endif
