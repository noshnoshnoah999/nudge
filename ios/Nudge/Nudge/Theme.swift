// Theme.swift — Nudge (iOS)
// Monochrome tinted themes, matching the StudyTrack look: the whole screen is one
// colour family (bg, cards, text, accent all share a hue), flat and cohesive.
// The selected palette lives in `Theme.palette`; AppSettings updates it and views
// that observe AppSettings re-render with the new colours.

import SwiftUI

// MARK: - Colour helpers

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        if h.count == 6 {
            self.init(red: Double((v >> 16) & 0xFF)/255.0,
                      green: Double((v >> 8) & 0xFF)/255.0,
                      blue: Double(v & 0xFF)/255.0)
        } else {
            self.init(red: 0.357, green: 0.310, blue: 0.812)
        }
    }
    init(lightHex: String, darkHex: String) {   // kept for compatibility
        self = Color(UIColor { tc in
            UIColor(tc.userInterfaceStyle == .dark ? Color(hex: darkHex) : Color(hex: lightHex))
        })
    }
}

// MARK: - Palette

struct Palette: Identifiable {
    let id: String
    let name: String
    let bg: String          // page background tint
    let card: String        // standard card fill (lighter tint)
    let cardStrong: String  // prominent card (e.g. hero "Next up")
    let hairline: String
    let text: String        // primary text (dark shade of the hue)
    let textSoft: String    // labels / secondary
    let accent: String      // saturated hue (numbers, active tab)
}

enum Palettes {
    static let all: [Palette] = [
        Palette(id: "mocha",    name: "Mocha",    bg: "CDB088", card: "E0CEAF", cardStrong: "BFA274", hairline: "BC9F71", text: "2E1F12", textSoft: "7C6038", accent: "5E3A1E"),
        Palette(id: "sage",     name: "Sage",     bg: "CFE1C5", card: "DFEAD6", cardStrong: "BFD3B2", hairline: "BDD2B1", text: "23391E", textSoft: "5C7A53", accent: "3C6A34"),
        Palette(id: "slate",    name: "Slate",    bg: "D4DAE3", card: "E5E9F0", cardStrong: "C3CCD9", hairline: "C2CAD6", text: "212833", textSoft: "5C6A7C", accent: "3C5167"),
        Palette(id: "rose",     name: "Rose",     bg: "ECD8D6", card: "F4E7E5", cardStrong: "DCC2C0", hairline: "DCC5C3", text: "3A2426", textSoft: "8A5E60", accent: "8C4A50"),
        Palette(id: "lavender", name: "Lavender", bg: "D9D2EC", card: "E8E3F4", cardStrong: "C6BDDF", hairline: "C7BEDF", text: "29243F", textSoft: "6A6294", accent: "5B4FCF"),
        Palette(id: "graphite", name: "Graphite", bg: "DBDCDF", card: "EBECEE", cardStrong: "C9CBCF", hairline: "C8CACE", text: "23252A", textSoft: "676C74", accent: "3A3E46"),
        Palette(id: "ocean",    name: "Ocean",    bg: "C8DEE2", card: "DBE9EC", cardStrong: "B6D0D5", hairline: "B6CFD3", text: "1B343A", textSoft: "4F7178", accent: "2C6670")
    ]
    static func by(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Theme (reads the current palette)

enum Theme {
    static var palette: Palette = Palettes.all[0]

    static var bg: Color         { Color(hex: palette.bg) }
    static var surface: Color    { Color(hex: palette.card) }
    static var surfaceAlt: Color { Color(hex: palette.cardStrong) }
    static var hairline: Color   { Color(hex: palette.hairline) }
    static var textMain: Color   { Color(hex: palette.text) }
    static var textMeta: Color   { Color(hex: palette.textSoft) }

    static var accent: Color     { Color(hex: palette.accent) }
    static var accentSoft: Color { Color(hex: palette.accent).opacity(0.14) }
    static var violet: Color     { accent }          // alias used across views
    static var violetSoft: Color { accentSoft }

    // Semantic colours used sparingly (overdue / done), kept readable on every tint.
    static var coral: Color   { Color(hex: "B14B3A") }   // muted brick — gentler on the warm bg
    static var coralBg: Color { Color(hex: "B14B3A").opacity(0.12) }
    static var sage: Color    { Color(hex: "4E7B54") }

    // Flat fills (no gradients — those read as tacky). Kept as gradients for API compat.
    static var violetGrad: LinearGradient { LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom) }
    static var coralGrad: LinearGradient  { LinearGradient(colors: [coral, coral], startPoint: .top, endPoint: .bottom) }

    static let cardShadow = Color.black

    static let spring  = Animation.spring(response: 0.40, dampingFraction: 0.78)
    static let snappy  = Animation.spring(response: 0.28, dampingFraction: 0.74)
    static let bouncy  = Animation.spring(response: 0.42, dampingFraction: 0.62)
}

// Back-compat aliases (computed so they track the current palette).
var bgColor: Color  { Theme.bg }
var violet: Color   { Theme.accent }
var coral: Color    { Theme.coral }
var textMain: Color { Theme.textMain }
var textMeta: Color { Theme.textMeta }

// MARK: - Reusable button style

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

extension View {
    /// Subtle soft shadow (kept very light — the tinted cards do most of the work).
    func cardElevation(_ radius: CGFloat = 8, y: CGFloat = 3, opacity: Double = 0.05) -> some View {
        shadow(color: Theme.cardShadow.opacity(opacity), radius: radius, y: y)
    }

    /// Staggered "pop" entrance — scales up from small, fades + de-blurs into place
    /// with a little overshoot. `index` cascades the rows so they arrive in sequence.
    func popIn(_ index: Int = 0, delayStep: Double = 0.045) -> some View {
        modifier(PopIn(index: index, delayStep: delayStep))
    }
}

/// One-shot entrance animation. Fires on appear; re-fires when the view's identity
/// changes (e.g. a parent `.id(query)`), so search results pop fresh on every query.
struct PopIn: ViewModifier {
    let index: Int
    var delayStep: Double = 0.045
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.82, anchor: .center)
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 5)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(Theme.bouncy.delay(Double(index) * delayStep)) { shown = true }
            }
    }
}
