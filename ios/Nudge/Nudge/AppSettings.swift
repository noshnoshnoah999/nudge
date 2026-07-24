// AppSettings.swift — Nudge (iOS)
// User preferences: which monochrome theme palette, and list density.
// Observed app-wide so changes apply live.
//
// CROSS-DEVICE SYNC (theme, boldText, compact)
//   These three appearance prefs sync across a user's signed-in devices via the existing
//   per-user Supabase `settings` row (whole-value, most-recent-write-wins — see CloudSync
//   `SettingsRow` and NudgeStore's settings bridge). celebrationFeedback, appLock, and
//   upcomingSections stay DEVICE-LOCAL on purpose (you may want silent/locked on one device).
//
//   Flow:
//     • Local change  → didSet writes to UserDefaults AND pushes to NudgeStore's synced
//       settings dict (which bumps the row stamp → next push uploads it).
//     • Cloud change  → NudgeStore.pullAll adopts a newer settings row, then calls
//       applyFromCloud(...) here. The `applyingFromCloud` guard makes the didSet update the
//       UI/UserDefaults WITHOUT pushing back — otherwise adopting a cloud value would
//       immediately re-upload it, ping-ponging the two devices forever.

import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    /// Keys shared with the cloud `settings` row. Kept in one place so the bridge and the
    /// apply path can't drift. Deliberately excludes celebrationFeedback/appLock/upcomingSections.
    enum SyncKey {
        static let theme = "theme"
        static let boldText = "boldText"
        static let compact = "compact"
    }

    /// The synced store, wired at launch via `attach(_:)` (mirrors sync/notifier.attach).
    /// Weak to avoid a retain cycle; nil when signed out or before attach.
    private weak var store: NudgeStore?

    /// True only while we're applying values that CAME FROM the cloud. Blocks the didSet
    /// observers from pushing those same values straight back up (the ping-pong guard).
    private var applyingFromCloud = false

    @Published var theme: String {
        didSet {
            Theme.palette = Palettes.by(theme)
            UserDefaults.standard.set(theme, forKey: K.theme)
            pushAppearanceIfLocal()
        }
    }
    @Published var compact: Bool {
        didSet {
            UserDefaults.standard.set(compact, forKey: K.compact)
            pushAppearanceIfLocal()
        }
    }
    @Published var appLock: Bool {
        didSet { UserDefaults.standard.set(appLock, forKey: K.appLock) }
    }
    /// Render all app text at bold weight. Applied app-wide via an environment font
    /// override at the root; explicitly-weighted text (some titles/buttons) may need
    /// per-view follow-up to pick this up.
    @Published var boldText: Bool {
        didSet {
            UserDefaults.standard.set(boldText, forKey: K.boldText)
            pushAppearanceIfLocal()
        }
    }
    /// List ids the user has chosen to surface as their own sections on the Upcoming
    /// tab, in display order (e.g. a "Subscriptions / Money" list pinned to the top).
    @Published var upcomingSections: [String] {
        didSet { UserDefaults.standard.set(upcomingSections, forKey: K.upcomingSections) }
    }
    /// Play the haptic + chime with the completion celebration animation. The visual always
    /// plays; this just mutes the feedback. Key shared with CelebrationOverlay via @AppStorage.
    /// DEVICE-LOCAL — intentionally not synced.
    @Published var celebrationFeedback: Bool {
        didSet { UserDefaults.standard.set(celebrationFeedback, forKey: K.celebrationFeedback) }
    }

    private enum K {
        static let theme = "pref.theme"
        static let compact = "pref.compact"
        static let appLock = "pref.appLock"
        static let boldText = "pref.boldText"
        static let upcomingSections = "pref.upcomingSections"
        static let celebrationFeedback = "pref.celebrationFeedback"
    }

    init() {
        var t = UserDefaults.standard.string(forKey: K.theme) ?? "mocha"
        if t == "tan" { t = "mocha" }    // renamed; keep existing installs on the brown theme
        theme = t
        compact = (UserDefaults.standard.object(forKey: K.compact) as? Bool) ?? true
        appLock = UserDefaults.standard.bool(forKey: K.appLock)
        boldText = UserDefaults.standard.bool(forKey: K.boldText)
        upcomingSections = (UserDefaults.standard.array(forKey: K.upcomingSections) as? [String]) ?? []
        celebrationFeedback = (UserDefaults.standard.object(forKey: K.celebrationFeedback) as? Bool) ?? true
        Theme.palette = Palettes.by(t)   // didSet doesn't fire on init's first assignment
    }

    // MARK: - Cross-device sync bridge

    /// Wire the synced store. Mirrors `RemindersSync.attach` / `NotificationManager.attach`,
    /// called once from NudgeApp at launch. Also seeds the cloud row with the current local
    /// appearance if the cloud has never carried these keys (so the first device to run the
    /// new build publishes its look rather than waiting for a change).
    func attach(_ store: NudgeStore) {
        self.store = store
        // Adopt whatever the cloud already has (e.g. the OTHER device set the theme before
        // this build ran here) …
        let a = store.cloudAppearance()
        applyFromCloud(theme: a.theme, boldText: a.boldText, compact: a.compact)
        // … then, if the cloud carries none of these keys yet, seed it with this device's look.
        store.seedAppearanceIfMissing(theme: theme, boldText: boldText, compact: compact)
        // Register for future cloud updates (a change made on the other device after launch).
        store.onCloudAppearance = { [weak self] t, b, c in
            self?.applyFromCloud(theme: t, boldText: b, compact: c)
        }
    }

    /// Push the current appearance triple into the synced settings row — UNLESS we're mid
    /// cloud-apply (which would ping-pong). Called from every synced pref's didSet.
    private func pushAppearanceIfLocal() {
        guard !applyingFromCloud else { return }
        store?.applyLocalAppearance(theme: theme, boldText: boldText, compact: compact)
    }

    /// Adopt appearance values that arrived from the cloud. Sets the guard so the resulting
    /// didSet observers update UI/UserDefaults without re-pushing. Only assigns when the value
    /// actually differs, so we don't churn @Published for no reason.
    func applyFromCloud(theme cloudTheme: String?, boldText cloudBold: Bool?, compact cloudCompact: Bool?) {
        applyingFromCloud = true
        defer { applyingFromCloud = false }
        if let cloudTheme, cloudTheme != theme { theme = cloudTheme }
        if let cloudBold, cloudBold != boldText { boldText = cloudBold }
        if let cloudCompact, cloudCompact != compact { compact = cloudCompact }
    }

    // Themes are light-tinted; keep the system chrome light so tints render true.
    var colorScheme: ColorScheme? { .light }

    var accent: Color { Theme.accent }
    var accentSoft: Color { Theme.accentSoft }
    var accentGrad: LinearGradient { Theme.violetGrad }
}
