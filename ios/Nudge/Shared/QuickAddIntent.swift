// QuickAddIntent.swift — Nudge (shared between app + widget extension)
// The App Intent run by the Control Center control. It opens the app and asks
// it to present the New Reminder sheet. Also surfaces in Siri / Shortcuts.

import AppIntents

/// The full New Reminder form (Siri / Shortcuts).
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

/// Quick Catch — the fast "get a thought out of my head" popup. Claude assigns
/// a smart date + time; the user just confirms. This is what the Control Center
/// button runs.
struct QuickCatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Catch a Thought"
    static var description = IntentDescription("Jot a thought; Nudge picks a smart time for it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.requestQuickCatch()
        return .result()
    }
}
