// AppSettings.swift — Nudge (iOS)
// User preferences: which monochrome theme palette, and list density.
// Observed app-wide so changes apply live.

import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    @Published var theme: String {
        didSet { Theme.palette = Palettes.by(theme); UserDefaults.standard.set(theme, forKey: K.theme) }
    }
    @Published var compact: Bool {
        didSet { UserDefaults.standard.set(compact, forKey: K.compact) }
    }
    @Published var appLock: Bool {
        didSet { UserDefaults.standard.set(appLock, forKey: K.appLock) }
    }
    /// List ids the user has chosen to surface as their own sections on the Upcoming
    /// tab, in display order (e.g. a "Subscriptions / Money" list pinned to the top).
    @Published var upcomingSections: [String] {
        didSet { UserDefaults.standard.set(upcomingSections, forKey: K.upcomingSections) }
    }
    /// Play the haptic + chime with the completion celebration animation. The visual always
    /// plays; this just mutes the feedback. Key shared with CelebrationOverlay via @AppStorage.
    @Published var celebrationFeedback: Bool {
        didSet { UserDefaults.standard.set(celebrationFeedback, forKey: K.celebrationFeedback) }
    }

    private enum K {
        static let theme = "pref.theme"
        static let compact = "pref.compact"
        static let appLock = "pref.appLock"
        static let upcomingSections = "pref.upcomingSections"
        static let celebrationFeedback = "pref.celebrationFeedback"
    }

    init() {
        var t = UserDefaults.standard.string(forKey: K.theme) ?? "mocha"
        if t == "tan" { t = "mocha" }    // renamed; keep existing installs on the brown theme
        theme = t
        compact = (UserDefaults.standard.object(forKey: K.compact) as? Bool) ?? true
        appLock = UserDefaults.standard.bool(forKey: K.appLock)
        upcomingSections = (UserDefaults.standard.array(forKey: K.upcomingSections) as? [String]) ?? []
        celebrationFeedback = (UserDefaults.standard.object(forKey: K.celebrationFeedback) as? Bool) ?? true
        Theme.palette = Palettes.by(t)   // didSet doesn't fire on init's first assignment
    }

    // Themes are light-tinted; keep the system chrome light so tints render true.
    var colorScheme: ColorScheme? { .light }

    var accent: Color { Theme.accent }
    var accentSoft: Color { Theme.accentSoft }
    var accentGrad: LinearGradient { Theme.violetGrad }
}
