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
        // later, in NotificationManager.attach(), once the SwiftUI scene exists.
        //
        // Because the delegate is attached AFTER didFinishLaunching returns, UNUserNotification-
        // Center will not deliver a tap that LAUNCHED the app to it. That is precisely why
        // NudgeSceneDelegate + NotificationManager.pendingColdTap exist below — they are the
        // cold-launch path, and removing them would silently break tapping a notification while
        // Nudge is fully quit. They are load-bearing, not leftover workaround.
        //
        // (The original note here claimed attaching the delegate early "delivers a launch tap
        // into the half-built window and UIKit asserts". That diagnosis was wrong — see the
        // correction on shouldSaveSecureApplicationState below. Attaching early may well be
        // safe now, but it has not been tested, so the working arrangement stands.)
        MainActor.assumeIsolated { NotificationManager.shared.registerCategories() }
        // Security: move any plaintext Anthropic key from UserDefaults into the Keychain and
        // delete the plaintext copy. One-time, no-op after the first migrated launch.
        APIKeyStore.migrateFromUserDefaultsIfNeeded()
        // Build the geofence manager here too, for the same reason: the OS relaunches us
        // straight into a region event with no scene, so the `.task` that syncs regions never
        // runs. CLLocationManager only delivers to a delegate that already exists at launch.
        MainActor.assumeIsolated { _ = LocationMonitor.shared }
        // Register the overnight carry-over background task before launch finishes (required
        // by BGTaskScheduler). Scheduling the first request happens when we go to background.
        #if !targetEnvironment(macCatalyst)
        CarryOverBGTask.register()
        #endif
        return true
    }

    // Nudge keeps no UIKit state to restore (SwiftUI owns the UI), so opting out saves UIKit
    // the work of building a restoration archive on background/launch events.
    //
    // CORRECTION (2026-08-04): this was originally added believing it would stop the
    // notification-tap crash. It did not, and could not. UIKit's
    // `_updateSnapshotAndStateRestorationWithAction:` still runs the `updateSnapshot:` half
    // regardless of this opt-out, and the snapshot — not the archive — was what asserted.
    // The real cause was the notification delegate being a `nonisolated async` method whose
    // completion handler therefore ran off the main thread; see the long comment on
    // `userNotificationCenter(_:didReceive:withCompletionHandler:)` in Notifications.swift.
    // These two lines are kept because they are harmless and mildly useful, NOT because they
    // fix anything.
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
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootContainer()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(notifier)
                .environmentObject(settings)
                // Bold Text: a root-level .fontWeight() overrides the weight of ALL descendant
                // text — even views that set their own .font(.headline) etc. — because weight is
                // a separate modifier from font. This catches the ~270 .font(...) calls that don't
                // pin their own weight. (Requires iOS 16+; deployment target is well past that.)
                // Views that DO set an explicit weight keep it; those are the only stragglers.
                // `effectiveBoldText`, not `boldText`: minimal mode ignores the Bold Text
                // preference entirely (see AppSettings), because bolding every glyph destroys
                // the light-body / heavy-title contrast the minimal design depends on.
                .fontWeight(settings.effectiveBoldText ? .bold : nil)
                // nil in minimal → system control colours (green switches, blue carets), which
                // is what Reminders shows. See AppSettings.controlTint.
                .tint(settings.controlTint)
                .preferredColorScheme(settings.colorScheme)
                // Touching `shared` here builds the CLLocationManager at launch, which is what
                // lets the OS relaunch us straight into a region event. Its delegate must exist
                // before any geofence can fire.
                .task {
                    sync.attach(store); notifier.attach(store); settings.attach(store)
                    // Clear/set the window's interface style override. Must run after the
                    // scene exists, and again on every foreground because SwiftUI reapplies
                    // `preferredColorScheme` and a scene can be rebuilt. See the doc comment
                    // on applyWindowAppearance() — this is what fixed Settings rendering light
                    // while the rest of the app was dark.
                    settings.applyWindowAppearance()
                    LocationMonitor.shared.sync(reminders: store.reminders)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        settings.applyWindowAppearance()
                        LocationMonitor.shared.sync(reminders: store.reminders)
                    }
                }
                .onOpenURL { url in
                    // Lock Screen quick-add widget deep link → open the same Quick Catch
                    // chooser as the Control Centre button (Quick Note vs Reminder).
                    if url.scheme == "nudge", url.host == "quickadd" {
                        AppRouter.shared.requestQuickCatch()
                    }
                    // External deep link for other apps (e.g. StudyTrack) to jump into Nudge.
                    if url.scheme == "nudgeapp" {
                        switch url.host {
                        case "add":
                            AppRouter.shared.requestQuickAdd()
                        default:
                            break // "open" (or anything else) just brings the app to the front
                        }
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
