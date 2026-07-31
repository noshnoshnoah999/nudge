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
        Palette(id: "lavender", name: "Lavender", bg: "C7AAE0", card: "D6C0EB", cardStrong: "AC85D2", hairline: "A379CC", text: "201433", textSoft: "573C7E", accent: "5A25A0"),
        Palette(id: "graphite", name: "Graphite", bg: "DBDCDF", card: "EBECEE", cardStrong: "C9CBCF", hairline: "C8CACE", text: "23252A", textSoft: "676C74", accent: "3A3E46"),
        Palette(id: "ocean",    name: "Ocean",    bg: "C3DBEC", card: "D8E9F5", cardStrong: "AFCFE6", hairline: "AECDE3", text: "122D42", textSoft: "4A7290", accent: "1B5C8C"),
        Palette(id: "orange",   name: "Orange",   bg: "D8885A", card: "DF9D77", cardStrong: "DD672C", hairline: "A8441C", text: "3D1A0B", textSoft: "633520", accent: "7A2A0E"),
        Palette(id: "red",      name: "Red",      bg: "E8ADA4", card: "EEC1B9", cardStrong: "D68D82", hairline: "A34B3F", text: "350F0D", textSoft: "843A34", accent: "6E1108")
    ]
    static func by(_ id: String) -> Palette { all.first { $0.id == id } ?? all[0] }
}

// MARK: - Theme (reads the current palette)

enum Theme {
    static var palette: Palette = Palettes.all[0]

    /// MINIMAL DESIGN — the flat, Apple-Reminders-style layout (the old "1 · Minimal" preview).
    ///
    /// This is a LAYOUT mode, not a colour theme. An earlier attempt shipped it as two extra
    /// palettes ("Plain" / "Plain Dark") which kept Nudge's tinted card structure and merely
    /// squared it off — the result looked like a washed-out Nudge, not the minimal design, and
    /// was rejected. So minimal is now its own switch, and while it's on the eight colour
    /// palettes are IGNORED ENTIRELY in favour of UIKit's semantic colours.
    ///
    /// Using semantic colours (rather than fixed light/dark hexes) is what makes minimal follow
    /// iOS's own Light/Dark setting for free: `AppSettings.colorScheme` returns nil in minimal,
    /// so the system decides, and every colour below resolves itself per trait collection.
    /// There is deliberately no in-app light/dark picker.
    ///
    /// Set from `AppSettings.minimalDesign` (init + didSet), same as `palette`.
    static var minimalDesign: Bool = false
    static var minimal: Bool { minimalDesign }

    static var bg: Color         { minimal ? Color(.systemBackground)          : Color(hex: palette.bg) }
    /// A card fill. In minimal this is `secondarySystemBackground` — a visible dark grey on a
    /// black page, exactly like a grouped cell in Settings or the Reminders edit sheet.
    ///
    /// It was `systemBackground` (i.e. the same as the page) in the previous build, on the
    /// theory that minimal has no cards at all. That's true of the reminder LIST, which draws
    /// no fill — but it made every other card (the Home stat tiles, the Lists grid, Settings
    /// rows) invisible, leaving only their borders showing. That's why the app was covered in
    /// hollow outlined rectangles. Cards get a fill and lose their border, not the reverse.
    static var surface: Color    { minimal ? Color(.secondarySystemBackground) : Color(hex: palette.card) }
    static var surfaceAlt: Color { minimal ? Color(.tertiarySystemBackground)  : Color(hex: palette.cardStrong) }
    static var hairline: Color   { minimal ? Color(.separator)                 : Color(hex: palette.hairline) }
    static var textMain: Color   { minimal ? Color(.label)                     : Color(hex: palette.text) }
    static var textMeta: Color   { minimal ? Color(.secondaryLabel)            : Color(hex: palette.textSoft) }

    /// Outline colour for a card-shaped container.
    ///
    /// **Transparent in minimal.** Apple's grouped UI separates a card from the page with a
    /// FILL, never a stroke — there is not a single 1pt outlined box in Reminders or Settings.
    /// Every "there are still outlines" report traced back to a
    /// `.stroke(Theme.hairline)` on a rounded rect, so they all read this instead.
    ///
    /// `Theme.hairline` is still the right colour for a DIVIDER between rows; this is only for
    /// borders around a shape.
    static var cardStroke: Color { minimal ? .clear : hairline }

    /// Minimal's accent is **system blue** — Apple's own control colour, and what Reminders
    /// uses for its title, its values ("Today", "7:50"), its ＋ button and its confirm button.
    ///
    /// This was `Color(.label)` (pure monochrome) in the first minimal build. That broke real
    /// controls: SwiftUI tints `Toggle` with the app accent, so in dark mode an ON switch was a
    /// white track under a white knob — the "strange looking" Minimal design toggle. Monochrome
    /// also isn't actually what Reminders does; it's a minimal app WITH one accent colour.
    static var accent: Color     { minimal ? Color(.systemBlue) : Color(hex: palette.accent) }
    static var accentSoft: Color { accent.opacity(minimal ? 0.16 : 0.14) }

    /// Tint for SwiftUI controls (Toggle, Picker, Stepper, ProgressView, DatePicker).
    ///
    /// **nil in minimal** = no override, so iOS supplies its own: a GREEN switch and a BLUE
    /// caret, which is what Reminders shows. Forcing `accent` onto a Toggle is what produced
    /// the white-track/white-knob switches Noah reported. Mirrors `AppSettings.controlTint`,
    /// for views that don't hold an AppSettings.
    static var controlTint: Color? { minimal ? nil : accent }
    static var violet: Color     { accent }          // alias used across views
    static var violetSoft: Color { accentSoft }

    /// Text/icon colour to use ON TOP OF an `accent`-filled shape (primary buttons, the
    /// selected day pill, the toast bars).
    ///
    /// Every tinted palette has a DARK accent, so white sat on it fine and the app hardcoded
    /// `.white` in ~30 places. Minimal breaks that assumption: in iOS dark mode its accent is
    /// WHITE, and white-on-white is invisible. `systemBackground` is the exact inverse of
    /// `label` in both appearances, so it's always readable.
    static var onAccent: Color { minimal ? Color(.systemBackground) : .white }

    /// Same idea for the `coral` (overdue / destructive) fill. System red stays dark enough in
    /// both appearances that white reads on it, so minimal keeps white here.
    static var onCoral: Color { .white }

    /// Text colour on the toast/selection bars, which fill with `textMain` to invert against
    /// the page. In minimal dark mode `textMain` is WHITE, so hardcoded white text there would
    /// be invisible — this flips to the page background instead.
    static var onTextMain: Color { minimal ? Color(.systemBackground) : .white }

    // Semantic colours used sparingly (overdue / done), kept readable on every tint.
    // On the orange/red palettes the default brick tone collides with the warm
    // background (too close in hue+lightness to read as "alert"), so those two
    // palettes get a deeper maroon that keeps real contrast against their cards.
    private static var coralHex: String {
        switch palette.id {
        case "orange", "red": return "6E1810"
        default: return "B14B3A"
        }
    }
    /// Overdue red. Minimal is otherwise monochrome, but overdue keeps colour on purpose:
    /// going fully greyscale deletes the only at-a-glance signal that something is late, which
    /// is a real usability loss rather than a style choice. `systemRed` self-adjusts for dark.
    static var coral: Color   { minimal ? Color(.systemRed) : Color(hex: coralHex) }
    static var coralBg: Color { coral.opacity(0.12) }
    /// "Done" green — neutralised in minimal so completion reads as grey, not celebratory.
    static var sage: Color    { minimal ? Color(.secondaryLabel) : Color(hex: "4E7B54") }

    // Flat fills (no gradients — those read as tacky). Kept as gradients for API compat.
    static var violetGrad: LinearGradient { LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom) }
    static var coralGrad: LinearGradient  { LinearGradient(colors: [coral, coral], startPoint: .top, endPoint: .bottom) }

    static let cardShadow = Color.black

    // MARK: - Shape
    //
    // Card geometry is read from here rather than hardcoded per view, so minimal can flatten
    // the whole app from one place instead of editing ~90 views.

    /// Corner radius for cards.
    ///
    /// Minimal clamps to 10 rather than flattening to 0. Zero was wrong: Apple's grouped cards
    /// (Reminders' edit sheet, Settings, the Health tiles) are all softly rounded — squaring
    /// them off made every container read as a hard-edged box, which is *louder* than the
    /// rounded original, not quieter. The minimal reminder ROWS are still perfectly square,
    /// because they pass 0 explicitly through `cardSurface` and draw no shape at all.
    static func radius(_ normal: CGFloat) -> CGFloat { minimal ? min(normal, 10) : normal }
    /// Horizontal page inset for the scrolling content. 24pt in minimal, matching the design
    /// this was copied from — the generous margin is a big part of why it reads as calm.
    static var rowInset: CGFloat { minimal ? 24 : 18 }
    /// Vertical padding inside a minimal reminder row. Kept fairly tight (10pt) on purpose:
    /// the first minimal build used 13pt with a full-bleed rule and the rows read as floating
    /// blobs of text rather than a list. Tighter rows + an inset rule is what makes a list
    /// scan as a list.
    static var rowVerticalPadding: CGFloat { 10 }
    /// Gap between the completion circle and the text column in a minimal row, and therefore
    /// how far the divider under it is inset. One constant so the two can't drift — if they
    /// disagree the rule looks misaligned with the text above it.
    static let minimalRowTextInset: CGFloat = 36
    /// Gap between sections. Minimal separates by whitespace alone, so it needs more of it.
    static var sectionSpacing: CGFloat { minimal ? 30 : 20 }

    // MARK: - Motion
    //
    // In minimal every animation collapses to a zero-duration step. Views keep calling
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
        // Minimal: no press scale, no fade. A button either is pressed or isn't.
        let s = Theme.minimal ? 1 : scale
        return configuration.label
            .scaleEffect(configuration.isPressed ? s : 1)
            .opacity(configuration.isPressed ? (Theme.minimal ? 0.6 : 0.9) : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

extension View {
    /// Subtle soft shadow (kept very light — the tinted cards do most of the work).
    /// Fully suppressed in minimal: flat rows sit on the page, they don't float above it.
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
    /// In minimal this is a no-op: content is simply there when the screen appears.
    @ViewBuilder
    func popIn(_ index: Int = 0, delayStep: Double = 0.045) -> some View {
        if Theme.minimal {
            self
        } else {
            modifier(PopIn(index: index, delayStep: delayStep))
        }
    }

    /// Card container for a reminder-style block.
    ///
    /// Tinted themes: a rounded, filled, bordered card, exactly as before.
    ///
    /// Minimal: **no fill and no border at all** — just a hairline divider underneath, so rows
    /// read as lines of text separated by rules rather than as boxes. This is the difference
    /// that mattered. The previous attempt kept the fill and border and only removed the corner
    /// radius, which produced squared-off cards — visually still Nudge, just uglier. A minimal
    /// list is defined by the ABSENCE of the container, not by its shape.
    ///
    /// `showsDivider: false` for the last row in a section.
    ///
    /// `dividerInset` shifts the rule's left edge inward so it starts where the TEXT starts,
    /// not at the circle — the way Reminders, Mail and Settings all do it. This inset is what
    /// makes a row read as one object: the ruled line visually belongs to the text column, so
    /// the circle and its title group together. A full-bleed rule instead cuts the screen into
    /// horizontal bands and the rows stop feeling like units. It does more work than making the
    /// line brighter, which is the obvious-but-wrong fix.
    ///
    /// `emphasis` still draws something in minimal for selected rows — a leading bar rather
    /// than a box, because a full outline would put the card back.
    @ViewBuilder
    func cardSurface(radius normal: CGFloat,
                     fill: Color = Theme.surface,
                     border: Color = Theme.hairline,
                     borderWidth: CGFloat? = nil,
                     showsDivider: Bool = true,
                     dividerInset: CGFloat = 0,
                     emphasis: Color? = nil) -> some View {
        if Theme.minimal {
            self
                .overlay(alignment: .bottom) {
                    if showsDivider {
                        // Spacer + rule rather than `.padding(.leading:)`, so the inset is
                        // unambiguous regardless of how the overlay sizes itself.
                        HStack(spacing: 0) {
                            Color.clear.frame(width: dividerInset, height: 0.5)
                            Rectangle().fill(Theme.hairline).frame(height: 0.5)
                        }
                    }
                }
                .overlay(alignment: .leading) {
                    if let e = emphasis {
                        Rectangle().fill(e).frame(width: 3)
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
