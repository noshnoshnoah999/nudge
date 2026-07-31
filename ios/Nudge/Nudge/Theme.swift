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
    /// True for palettes whose background is dark. Drives the app's `colorScheme`, so system
    /// chrome (keyboard, sheets, date wheels, context menus) matches instead of staying light.
    var isDark: Bool = false
    /// "Plain" mode — the deliberately boring, low-stimulation look modelled on Apple
    /// Reminders. Colour is neutral, and on top of that the app suppresses its entrance
    /// animations, card shadows, spring transitions and completion flair, and squares the
    /// cards off into flat rows. See `Theme.minimal` for the switches this feeds.
    var minimal: Bool = false
}

enum Palettes {
    static let all: [Palette] = [
        Palette(id: "mocha",    name: "Mocha",    bg: "C2986A", card: "D6B689", cardStrong: "AD8358", hairline: "AA7F52", text: "2A1608", textSoft: "6E4A22", accent: "5E3A1E"),
        Palette(id: "sage",     name: "Sage",     bg: "CFE1C5", card: "DFEAD6", cardStrong: "BFD3B2", hairline: "BDD2B1", text: "23391E", textSoft: "5C7A53", accent: "3C6A34"),
        Palette(id: "rose",     name: "Rose",     bg: "F5D9E3", card: "FAEAF0", cardStrong: "EABDD0", hairline: "E9C0D2", text: "3D1B2C", textSoft: "96566F", accent: "B33A6B"),
        Palette(id: "lavender", name: "Lavender", bg: "C7AAE0", card: "D6C0EB", cardStrong: "AC85D2", hairline: "A379CC", text: "201433", textSoft: "573C7E", accent: "5A25A0"),
        Palette(id: "graphite", name: "Graphite", bg: "DBDCDF", card: "EBECEE", cardStrong: "C9CBCF", hairline: "C8CACE", text: "23252A", textSoft: "676C74", accent: "3A3E46"),
        Palette(id: "ocean",    name: "Ocean",    bg: "C3DBEC", card: "D8E9F5", cardStrong: "AFCFE6", hairline: "AECDE3", text: "122D42", textSoft: "4A7290", accent: "1B5C8C"),
        Palette(id: "orange",   name: "Orange",   bg: "D8885A", card: "DF9D77", cardStrong: "DD672C", hairline: "A8441C", text: "3D1A0B", textSoft: "633520", accent: "7A2A0E"),
        Palette(id: "red",      name: "Red",      bg: "E8ADA4", card: "EEC1B9", cardStrong: "D68D82", hairline: "A34B3F", text: "350F0D", textSoft: "843A34", accent: "6E1108"),

        // MARK: Plain (minimal / "dumb phone") — deliberately boring, Apple Reminders-ish.
        // Neutral greys only, no hue. Values are Apple's own system greys so the app sits
        // flush with native chrome instead of fighting it.
        Palette(id: "plain",     name: "Plain",      bg: "F2F2F7", card: "FFFFFF", cardStrong: "E5E5EA", hairline: "D1D1D6", text: "000000", textSoft: "8E8E93", accent: "3A3A3C",
                isDark: false, minimal: true),
        Palette(id: "plainDark", name: "Plain Dark", bg: "000000", card: "1C1C1E", cardStrong: "2C2C2E", hairline: "38383A", text: "FFFFFF", textSoft: "8E8E93", accent: "AEAEB2",
                isDark: true,  minimal: true)
    ]
    static func by(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Theme (reads the current palette)

enum Theme {
    static var palette: Palette = Palettes.all[0]

    /// Plain / low-stimulation mode is a property of the selected palette, not a separate
    /// setting — picking "Plain" or "Plain Dark" IS the switch. That keeps it on the existing
    /// cross-device `theme` sync path with no new key to store or migrate.
    static var minimal: Bool { palette.minimal }
    static var isDark: Bool  { palette.isDark }

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

    /// Text/icon colour to use ON TOP OF an `accent`-filled shape (primary buttons, the
    /// selected day pill, the toast bars).
    ///
    /// Every tinted palette has a DARK accent, so white sat on it fine and the app hardcoded
    /// `.white` in ~30 places. "Plain Dark" breaks that assumption: its accent is a LIGHT grey
    /// (#AEAEB2) because the accent also has to read as text on a black page. White-on-#AEAEB2
    /// is unreadable, so those call sites now ask for this instead of assuming white.
    static var onAccent: Color { isDark ? Color(hex: palette.bg) : .white }

    /// Same idea for the `coral` (overdue / destructive) fill.
    static var onCoral: Color { isDark ? Color(hex: palette.bg) : .white }

    /// Text colour on the toast/selection bars, which fill with `textMain` to invert against
    /// the page. On a dark palette `textMain` is WHITE, so hardcoded white text there would be
    /// invisible — this flips to the page background instead.
    static var onTextMain: Color { isDark ? Color(hex: palette.bg) : .white }

    // Semantic colours used sparingly (overdue / done), kept readable on every tint.
    // On the orange/red palettes the default brick tone collides with the warm
    // background (too close in hue+lightness to read as "alert"), so those two
    // palettes get a deeper maroon that keeps real contrast against their cards.
    private static var coralHex: String {
        switch palette.id {
        case "orange", "red": return "6E1810"
        // Plain deliberately drops hue everywhere EXCEPT overdue. Going fully greyscale
        // would delete the only at-a-glance signal that something is late, which is a real
        // usability loss, not just a style choice. So overdue keeps a muted, desaturated red
        // — legible on each plain background without being loud.
        case "plain":     return "A03A28"
        case "plainDark": return "C97567"
        default: return "B14B3A"
        }
    }
    static var coral: Color   { Color(hex: coralHex) }
    static var coralBg: Color { Color(hex: coralHex).opacity(0.12) }
    /// "Done" green — neutralised in plain mode so completion reads as grey, not celebratory.
    static var sage: Color    { Color(hex: minimal ? palette.textSoft : "4E7B54") }

    // Flat fills (no gradients — those read as tacky). Kept as gradients for API compat.
    static var violetGrad: LinearGradient { LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom) }
    static var coralGrad: LinearGradient  { LinearGradient(colors: [coral, coral], startPoint: .top, endPoint: .bottom) }

    static let cardShadow = Color.black

    // MARK: - Shape
    //
    // Card geometry is read from here rather than hardcoded per view, so plain mode can
    // square everything off into Apple-Reminders-style flat rows from one place.

    /// Corner radius for cards. 0 in plain mode → rows, not floating cards.
    static func radius(_ normal: CGFloat) -> CGFloat { minimal ? 0 : normal }
    /// Border width around a card. Plain mode uses a single hairline divider instead of a
    /// full box outline, so the standard border is dropped to zero.
    static var cardBorderWidth: CGFloat { minimal ? 0 : 1 }
    /// Horizontal page inset for the scrolling content.
    ///
    /// Plain mode keeps a modest 16pt inset rather than going truly edge-to-edge like Apple
    /// Reminders. True full-bleed would drop the section headers ("TODAY", "OVERDUE") and the
    /// empty-state text flush against the screen edge, which looks broken — making that work
    /// properly means re-padding text separately from rows in six tabs. Squared corners, zero
    /// row gap and hairline dividers already carry the list feel, so this trades the last 16pt
    /// for not touching every view. Revisit if the inset reads as too card-like on device.
    static var rowInset: CGFloat { minimal ? 16 : 18 }

    // MARK: - Motion
    //
    // In plain mode every animation collapses to a zero-duration step. Views keep calling
    // `withAnimation(Theme.spring)` unchanged; the movement simply doesn't happen. This is
    // why nothing outside this file needs an `if minimal` branch for motion.

    private static let instant = Animation.linear(duration: 0)
    static var spring: Animation { minimal ? instant : .spring(response: 0.40, dampingFraction: 0.78) }
    static var snappy: Animation { minimal ? instant : .spring(response: 0.28, dampingFraction: 0.74) }
    static var bouncy: Animation { minimal ? instant : .spring(response: 0.42, dampingFraction: 0.62) }
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
        // Plain mode: no press scale, no fade. A button either is pressed or isn't.
        let s = Theme.minimal ? 1 : scale
        return configuration.label
            .scaleEffect(configuration.isPressed ? s : 1)
            .opacity(configuration.isPressed ? (Theme.minimal ? 0.6 : 0.9) : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

extension View {
    /// Subtle soft shadow (kept very light — the tinted cards do most of the work).
    /// Fully suppressed in plain mode: flat rows sit on the page, they don't float above it.
    @ViewBuilder
    func cardElevation(_ radius: CGFloat = 8, y: CGFloat = 3, opacity: Double = 0.05) -> some View {
        if Theme.minimal {
            self
        } else {
            shadow(color: Theme.cardShadow.opacity(opacity), radius: radius, y: y)
        }
    }

    /// Staggered "pop" entrance — scales up from small, fades + de-blurs into place
    /// with a little overshoot. `index` cascades the rows so they arrive in sequence.
    /// In plain mode this is a no-op: content is simply there when the screen appears.
    @ViewBuilder
    func popIn(_ index: Int = 0, delayStep: Double = 0.045) -> some View {
        if Theme.minimal {
            self
        } else {
            modifier(PopIn(index: index, delayStep: delayStep))
        }
    }

    /// Card container for a reminder-style block. In the tinted themes this is a rounded,
    /// bordered card; in plain mode it collapses to a flat full-width row with a single
    /// bottom hairline, matching Apple Reminders.
    ///
    /// `border` overrides the resting border colour (used for the overdue / selected states),
    /// and `borderWidth` forces a visible outline even in plain mode — selection still needs
    /// to be unmistakable, boring or not.
    @ViewBuilder
    func cardSurface(radius normal: CGFloat,
                     fill: Color = Theme.surface,
                     border: Color = Theme.hairline,
                     borderWidth: CGFloat? = nil) -> some View {
        if Theme.minimal {
            self
                .background(fill)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                }
                .overlay {
                    // Only draw a box when a caller explicitly asks for one (selection).
                    if let w = borderWidth, w > 0 {
                        Rectangle().strokeBorder(border, lineWidth: w)
                    }
                }
        } else {
            self
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: normal, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: normal, style: .continuous)
                    .strokeBorder(border, lineWidth: borderWidth ?? 1))
        }
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
