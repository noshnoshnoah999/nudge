// AppRouter.swift — Nudge (shared between app + widget extension)
// A tiny singleton the Control Center intent flips to ask the app to open
// quick-add. The intent runs in-app (openAppWhenRun), so it mutates the same
// instance ContentView observes.

import SwiftUI
import Combine

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingQuickAdd: Bool = false
    @Published var pendingClaudePrompt: String? = nil   // set when a new "Claude - " reminder is saved
    @Published var pendingReschedule: String? = nil      // reminder id to reschedule (from a notification)
    private init() {}
    func requestQuickAdd() { pendingQuickAdd = true }
}
