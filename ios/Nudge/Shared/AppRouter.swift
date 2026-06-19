// AppRouter.swift — Nudge (shared between app + widget extension)
// A tiny singleton the Control Center intent flips to ask the app to open
// quick-add. The intent runs in-app (openAppWhenRun), so it mutates the same
// instance ContentView observes.

import SwiftUI
import Combine

/// A notification action handed to the app to run once it's live — used when a notification
/// is tapped from a FULLY-QUIT state, where doing the work inside the delegate (touching the
/// store / widgets / UI during UIKit's launch + state-restoration snapshot) makes UIKit abort.
struct NotifAction: Equatable { let action: String; let rid: String }

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var pendingQuickAdd: Bool = false
    @Published var pendingClaudePrompt: String? = nil   // set when a new "Claude - " reminder is saved
    @Published var pendingReschedule: String? = nil      // reminder id to reschedule (from a notification)
    @Published var pendingShopping: Bool = false         // open the Shopping list (pay-day notification tap)
    @Published var pendingNotification: NotifAction? = nil   // deferred cold-launch notification tap
    private init() {}
    func requestQuickAdd() { pendingQuickAdd = true }
}
