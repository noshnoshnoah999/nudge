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
        Palette(id: "mocha",    name: "Mocha",    bg: "C2986A", card: "D6B689", cardStrong: "AD8358", hairline: "AA7F52", text: "2A1608", textSoft: "6E4A22", accent: "5E3A1E"),
        Palette(id: "sage",     name: "Sage",     bg: "CFE1C5", card: "DFEAD6", cardStrong: "BFD3B2", hairline: "BDD2B1", text: "23391E", textSoft: "5C7A53", accent: "3C6A34"),
        Palette(id: "rose",     name: "Rose",     bg: "F5D9E3", card: "FAEAF0", cardStrong: "EABDD0", hairline: "E9C0D2", text: "3D1B2C", textSoft: "96566F", accent: "B33A6B"),
        Palette(id: "lavender", name: "Lavender", bg: "DECBEF", card: "ECDFF6", cardStrong: "C9ADE3", hairline: "CBB0E3", text: "2B1D40", textSoft: "6A4B94", accent: "6B2FB8"),
        Palette(id: "graphite", name: "Graphite", bg: "DBDCDF", card: "EBECEE", cardStrong: "C9CBCF", hairline: "C8CACE", text: "23252A", textSoft: "676C74", accent: "3A3E46"),
        Palette(id: "ocean",    name: "Ocean",    bg: "C3DBEC", card: "D8E9F5", cardStrong: "AFCFE6", hairline: "AECDE3", text: "122D42", textSoft: "4A7290", accent: "1B5C8C"),
        Palette(id: "orange",   name: "Orange",   bg: "F6D9BE", card: "FAE8D4", cardStrong: "EFC190", hairline: "EEBE8C", text: "452408", textSoft: "8C5A28", accent: "D9641A"),
        Palette(id: "red",      name: "Red",      bg: "F3D2CE", card: "F8E3E0", cardStrong: "E7B3AC", hairline: "E6ACA5", text: "401412", textSoft: "96453F", accent: "B8271F"),
        Palette(id: "yellow",   name: "Yellow",   bg: "FAF3D6", card: "FCF8E8", cardStrong: "F0DE8E", hairline: "EAD9A0", text: "3D3009", textSoft: "8A7530", accent: "A6820A")
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
