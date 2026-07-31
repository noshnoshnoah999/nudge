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
        static let minimalDesign = "minimalDesign"
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
    /// Minimal design — the flat, Apple-Reminders-style layout. While this is on, the eight
    /// colour palettes are ignored entirely and the app renders in UIKit semantic colours,
    /// which is what lets it follow iOS's own Light/Dark setting (see `colorScheme`).
    /// Synced across devices like the other appearance prefs.
    @Published var minimalDesign: Bool {
        didSet {
            Theme.minimalDesign = minimalDesign
            UserDefaults.standard.set(minimalDesign, forKey: K.minimalDesign)
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
        static let minimalDesign = "pref.minimalDesign"
    }

    init() {
        var t = UserDefaults.standard.string(forKey: K.theme) ?? "mocha"
        if t == "tan" { t = "mocha" }    // renamed; keep existing installs on the brown theme
        // The short-lived "Plain" / "Plain Dark" palettes (shipped in 85cc7f0, removed the same
        // week) no longer exist. Anyone left on one lands back on Mocha with the real minimal
        // design switched on instead, which is what they were reaching for.
        var startMinimal = UserDefaults.standard.bool(forKey: K.minimalDesign)
        if t == "plain" || t == "plainDark" { t = "mocha"; startMinimal = true }
        theme = t
        compact = (UserDefaults.standard.object(forKey: K.compact) as? Bool) ?? true
        appLock = UserDefaults.standard.bool(forKey: K.appLock)
        boldText = UserDefaults.standard.bool(forKey: K.boldText)
        minimalDesign = startMinimal
        upcomingSections = (UserDefaults.standard.array(forKey: K.upcomingSections) as? [String]) ?? []
        celebrationFeedback = (UserDefaults.standard.object(forKey: K.celebrationFeedback) as? Bool) ?? true
        // didSet doesn't fire on init's first assignment, so seed Theme's globals by hand.
        Theme.palette = Palettes.by(t)
        Theme.minimalDesign = startMinimal
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
        applyFromCloud(theme: a.theme, boldText: a.boldText, compact: a.compact,
                       minimalDesign: a.minimalDesign)
        // … then, if the cloud carries none of these keys yet, seed it with this device's look.
        store.seedAppearanceIfMissing(theme: theme, boldText: boldText, compact: compact,
                                      minimalDesign: minimalDesign)
        // Register for future cloud updates (a change made on the other device after launch).
        store.onCloudAppearance = { [weak self] t, b, c, m in
            self?.applyFromCloud(theme: t, boldText: b, compact: c, minimalDesign: m)
        }
    }

    /// Push the current appearance values into the synced settings row — UNLESS we're mid
    /// cloud-apply (which would ping-pong). Called from every synced pref's didSet.
    private func pushAppearanceIfLocal() {
        guard !applyingFromCloud else { return }
        store?.applyLocalAppearance(theme: theme, boldText: boldText, compact: compact,
                                    minimalDesign: minimalDesign)
    }

    /// Adopt appearance values that arrived from the cloud. Sets the guard so the resulting
    /// didSet observers update UI/UserDefaults without re-pushing. Only assigns when the value
    /// actually differs, so we don't churn @Published for no reason.
    func applyFromCloud(theme cloudTheme: String?, boldText cloudBold: Bool?,
                        compact cloudCompact: Bool?, minimalDesign cloudMinimal: Bool?) {
        applyingFromCloud = true
        defer { applyingFromCloud = false }
        // A theme id the cloud carries but this build no longer knows about (the removed
        // "plain" / "plainDark") must not be adopted — `Palettes.by` would silently fall back
        // to Mocha while `theme` still held the dead id, and the next local change would push
        // that dead id straight back up. Translate it to the real minimal switch instead.
        if let cloudTheme {
            if cloudTheme == "plain" || cloudTheme == "plainDark" {
                if theme != "mocha" { theme = "mocha" }
                if !minimalDesign { minimalDesign = true }
            } else if cloudTheme != theme {
                theme = cloudTheme
            }
        }
        if let cloudBold, cloudBold != boldText { boldText = cloudBold }
        if let cloudCompact, cloudCompact != compact { compact = cloudCompact }
        if let cloudMinimal, cloudMinimal != minimalDesign { minimalDesign = cloudMinimal }
    }

    /// System chrome (keyboard, sheets, date wheels, context menus, scroll indicators).
    ///
    /// The eight tinted themes are all light-backed, so they pin `.light` exactly as before —
    /// otherwise a phone in dark mode would render dark chrome on top of a pale tint.
    ///
    /// Minimal returns **nil**, which hands the decision back to iOS. That single nil is the
    /// whole of "minimal dark mode": the app has no light/dark picker of its own, it just
    /// inherits the phone's, and every Theme colour in minimal is a semantic UIColor that
    /// resolves itself per appearance. Turn on Dark Mode in iOS Settings and Nudge follows.
    var colorScheme: ColorScheme? { minimalDesign ? nil : .light }

    var accent: Color { Theme.accent }
    var accentSoft: Color { Theme.accentSoft }
    var accentGrad: LinearGradient { Theme.violetGrad }
}
