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

    private enum K {
        static let theme = "pref.theme"
        static let compact = "pref.compact"
        static let appLock = "pref.appLock"
    }

    init() {
        let t = UserDefaults.standard.string(forKey: K.theme) ?? "tan"
        theme = t
        compact = (UserDefaults.standard.object(forKey: K.compact) as? Bool) ?? true
        appLock = UserDefaults.standard.bool(forKey: K.appLock)
        Theme.palette = Palettes.by(t)   // didSet doesn't fire on init's first assignment
    }

    // Themes are light-tinted; keep the system chrome light so tints render true.
    var colorScheme: ColorScheme? { .light }

    var accent: Color { Theme.accent }
    var accentSoft: Color { Theme.accentSoft }
    var accentGrad: LinearGradient { Theme.violetGrad }
}
