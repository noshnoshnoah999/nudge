// QuickAddIntent.swift — Nudge (shared between app + widget extension)
// The App Intent run by the Control Center control. It opens the app and asks
// it to present the New Reminder sheet. Also surfaces in Siri / Shortcuts.

import AppIntents

struct QuickAddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Nudge"
    static var description = IntentDescription("Quickly capture a new reminder in Nudge.")
    // Bring the app to the foreground so we can show the capture field.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.requestQuickAdd()
        return .result()
    }
}
