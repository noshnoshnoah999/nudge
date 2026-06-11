// NudgeApp.swift — Nudge (iOS)
// Bundle ID: uk.flouty.nudge

import SwiftUI

@main
struct NudgeApp: App {
    @StateObject private var store = NudgeStore()
    @StateObject private var sync = RemindersSync()
    @StateObject private var notifier = NotificationManager()
    @StateObject private var settings = AppSettings()
    var body: some Scene {
        WindowGroup {
            RootContainer()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(notifier)
                .environmentObject(settings)
                .tint(settings.accent)
                .preferredColorScheme(settings.colorScheme)
                .task { sync.attach(store); notifier.attach(store) }
        }
    }
}
