// NudgeApp.swift — Nudge (iOS)
// Bundle ID: uk.flouty.nudge

import SwiftUI
import UIKit

/// Registers the notification delegate + action categories the instant the process
/// launches — before any SwiftUI view appears. Without this, a Complete/Snooze tap (or a
/// plain tap on Mac) that wakes the app from a fully-quit state isn't handled, because the
/// view `.task` that used to do the wiring never runs on a background launch.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Register only the action-button categories here. The notification DELEGATE is set
        // later (NotificationManager.attach, after the SwiftUI scene exists) — setting it this
        // early delivers a launch tap into the half-built window and UIKit asserts (crash).
        MainActor.assumeIsolated { NotificationManager.shared.registerCategories() }
        return true
    }

    // Nudge keeps no UIKit state to restore (SwiftUI owns the UI). Opting out stops UIKit
    // building a state-restoration archive on background/launch events — the codepath whose
    // assertion was crashing the app when a notification tap launched it from fully-quit.
    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }

    // Route scenes through our delegate so we can read the notification that LAUNCHED the app
    // (cold start) from the scene's connection options — the correct, crash-free moment. (A
    // tap while the app is already running is handled by the UNUserNotificationCenter delegate.)
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = NudgeSceneDelegate.self
        return config
    }
}

/// Captures a notification tap that launched the app from fully-quit. SwiftUI still owns the
/// window (we never create one here) — we only read the launching notification.
final class NudgeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let resp = connectionOptions.notificationResponse {
            NotificationManager.pendingColdTap = (resp.actionIdentifier, resp.notification.request.identifier)
        }
    }
}

@main
struct NudgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = NudgeStore()
    @StateObject private var sync = RemindersSync()
    @StateObject private var notifier = NotificationManager.shared
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
                .onOpenURL { url in
                    // Lock Screen quick-add widget deep link → open the New Reminder sheet.
                    if url.scheme == "nudge", url.host == "quickadd" {
                        AppRouter.shared.requestQuickAdd()
                    }
                }
        }
        // Mac: ⌘N (and File ▸ New Reminder) opens quick-add — the closest Mac-native
        // equivalent to the iOS Control Centre button (Apple doesn't allow third-party
        // Control Centre modules on macOS; the QuickAdd widget also works in Notification Centre).
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Reminder") { AppRouter.shared.requestQuickAdd() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
