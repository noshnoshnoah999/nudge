// TodayWidgetStyle.swift — Nudge widget extension
//
// Edit-mode styling for the large Today widget. On a free Apple team there's no App Group,
// so the app can't push style choices to the widget. Instead the user picks these in the
// widget's own Edit mode (long-press → Edit Widget), which is stored per-widget by the system
// via an AppIntent configuration — no shared container needed.
//
// Four controls: font (curated system fonts), text size, row spacing, and a grayscale toggle
// for the low-stimulation "dumb phone" look.
//
// NOTE: switching TodayWidget from StaticConfiguration to this AppIntentConfiguration will
// reset any already-placed Today widgets once (iOS treats the config-type change as a new
// widget). The user re-adds it and re-picks options a single time. This is a known one-time
// cost, not data loss.

import AppIntents
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Curated font choices (system fonts only — reliable in a widget)

enum WidgetFont: String, AppEnum {
    case system, rounded, serif, monospaced

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Font")
    static var caseDisplayRepresentations: [WidgetFont: DisplayRepresentation] = [
        .system:     "Default",
        .rounded:    "Rounded",
        .serif:      "Serif",
        .monospaced: "Monospace"
    ]

    /// The SwiftUI design this maps to.
    var design: Font.Design {
        switch self {
        case .system:     return .default
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        }
    }
}

// MARK: - Text size
//
// Numeric point size chosen in Edit mode. Widget configuration can't render a true drag
// slider, so this is an Int parameter with a valid range — iOS shows a tap-to-enter / stepper
// field so the user picks the exact number. Clamped to a sane widget range.

let widgetFontSizeRange: ClosedRange<Int> = 12...40
let widgetFontSizeDefault = 22   // big, Dumb-Phone-style default

// MARK: - Row spacing / density

enum WidgetSpacing: String, AppEnum {
    case compact, comfortable, airy

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spacing")
    static var caseDisplayRepresentations: [WidgetSpacing: DisplayRepresentation] = [
        .compact:     "Compact",
        .comfortable: "Comfortable",
        .airy:        "Airy"
    ]

    var rowSpacing: CGFloat {
        switch self {
        case .compact:     return 5
        case .comfortable: return 9   // current default
        case .airy:        return 14
        }
    }
}

// MARK: - Background colour
//
// Noah runs his Lock Screen / Home Screen with one of two near-black wallpapers
// (sampled directly from his device: #0B0B0B and #000000) to keep the phone
// low-stimulation. Matching the widget background to whichever one is active
// makes the widget visually disappear into the wallpaper instead of showing a
// grey system card. "System default" keeps the old `.background` material for
// anyone who wants the standard widget look.
enum WidgetBackground: String, AppEnum {
    case systemDefault, softBlack, trueBlack

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Background")
    static var caseDisplayRepresentations: [WidgetBackground: DisplayRepresentation] = [
        .systemDefault: "System Default",
        .softBlack:     "Soft Black (#0B0B0B)",
        .trueBlack:     "True Black (#000000)"
    ]

    /// nil means "use the system's default widget background material".
    var color: Color? {
        switch self {
        case .systemDefault: return nil
        case .softBlack:     return Color(wHex: "0B0B0B")
        case .trueBlack:     return Color(wHex: "000000")
        }
    }

    #if canImport(UIKit)
    /// The same colour as a 1-colour **image**.
    ///
    /// WHY THIS EXISTS — the important part of this file:
    ///
    /// In Apple's tinted Home Screen mode the widget renders in `.accented`. A flat `Color`
    /// used as `containerBackground` does NOT survive that mode: the system remaps it to its
    /// own elevated material. This was measured on-device, not assumed — screenshots of the
    /// Home Screen showed the wallpaper at #000000 and the Nudge card at **#181818**, even with
    /// True Black selected and `containerBackgroundRemovable(false)` already applied. So the
    /// background layer was being kept, but the *colour inside it* was being overridden.
    ///
    /// `Image` has an escape hatch that `Color` simply does not have:
    /// `.widgetAccentedRenderingMode(.fullColor)` tells the system to render the image in its
    /// original colours with no tint treatment at all. So instead of handing WidgetKit a
    /// colour it feels free to reinterpret, we hand it a solid-colour image it must leave alone.
    ///
    /// This is also, in effect, what third-party "transparent widget" apps do — they have the
    /// user attach a screenshot of an empty Home Screen page and draw it as the background
    /// image. Noah's wallpaper measures as a genuinely flat #000000, so there is no need for a
    /// real screenshot (and therefore no need for an App Group, which a free Apple team can't
    /// use anyway — see the free-team constraint): a generated flat image is pixel-identical to
    /// a screenshot of a flat wallpaper.
    ///
    /// Generated once and cached — these are tiny and the value never changes at runtime.
    var solidImage: UIImage? {
        switch self {
        case .systemDefault: return nil
        case .softBlack:     return Self.softBlackImage
        case .trueBlack:     return Self.trueBlackImage
        }
    }

    private static let softBlackImage =
        makeSolidImage(UIColor(red: 11/255, green: 11/255, blue: 11/255, alpha: 1))
    private static let trueBlackImage =
        makeSolidImage(UIColor(red: 0, green: 0, blue: 0, alpha: 1))

    /// A small opaque square of one colour. Stretched with `.resizable()` at render time, so
    /// the pixel size only needs to be big enough to avoid sampling artefacts.
    private static func makeSolidImage(_ color: UIColor,
                                       size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true            // no alpha — nothing for the system to luminance-map
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
    #endif
}

// MARK: - The configuration intent (what Edit mode presents)

struct TodayWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today Widget Style"
    static var description = IntentDescription("Customize the Today widget's font, size, spacing, and colour.")

    @Parameter(title: "Font", default: .system)
    var font: WidgetFont

    // Numeric font size (points). Range gives a stepper-style control in Edit mode.
    @Parameter(title: "Font size", default: 22,
               controlStyle: .stepper,
               inclusiveRange: (12, 40))
    var fontSize: Int

    @Parameter(title: "Spacing", default: .comfortable)
    var spacing: WidgetSpacing

    @Parameter(title: "Grayscale", default: false)
    var grayscale: Bool

    @Parameter(title: "Background", default: .systemDefault)
    var background: WidgetBackground
}

// MARK: - Resolved style passed into the view

/// A plain value bundling the resolved style so the view doesn't reach into the intent.
struct TodayStyle {
    var design: Font.Design
    var titleSize: CGFloat
    var rowSpacing: CGFloat
    var grayscale: Bool
    /// The chosen background as the enum, not a resolved `Color` — the view needs the enum so it
    /// can render the *image* form, which is what survives Apple's tinted mode. See
    /// `WidgetBackground.solidImage`.
    var background: WidgetBackground

    /// Convenience for the plain-colour form (used only where tint mode isn't a factor).
    var backgroundColor: Color? { background.color }

    static let `default` = TodayStyle(design: .default, titleSize: CGFloat(widgetFontSizeDefault),
                                      rowSpacing: 9, grayscale: false, background: .systemDefault)

    init(design: Font.Design, titleSize: CGFloat, rowSpacing: CGFloat, grayscale: Bool,
         background: WidgetBackground = .systemDefault) {
        self.design = design; self.titleSize = titleSize
        self.rowSpacing = rowSpacing; self.grayscale = grayscale
        self.background = background
    }

    init(_ c: TodayWidgetConfigIntent) {
        design = c.font.design
        // Clamp defensively in case an old config stored an out-of-range value.
        titleSize = CGFloat(min(max(c.fontSize, widgetFontSizeRange.lowerBound), widgetFontSizeRange.upperBound))
        rowSpacing = c.spacing.rowSpacing
        grayscale = c.grayscale
        background = c.background
    }
}

// MARK: - The background view itself

/// Renders the chosen widget background.
///
/// Uses an `Image` (not a `Color`) for the near-black presets, tagged
/// `.widgetAccentedRenderingMode(.fullColor)`, because that is the only way to stop Apple's
/// tinted Home Screen mode from remapping the colour to its own material. Measured on-device:
/// a `Color` came out #181818 against a #000000 wallpaper; the goal is an exact match so the
/// widget disappears. Falls back to the system material when "System Default" is chosen.
struct TodayWidgetBackground: View {
    let background: WidgetBackground

    var body: some View {
        #if canImport(UIKit)
        if let image = background.solidImage {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
        } else {
            // "System Default" — draw nothing and let the widget's own container background
            // show through unchanged, so the default look is completely untouched.
            Color.clear
        }
        #else
        // No UIKit (so no image generation) — fall back to the flat colour. This path is not
        // used on iOS/macCatalyst, which is where the tinted-mode problem exists.
        if let color = background.color {
            Rectangle().fill(color)
        } else {
            Color.clear
        }
        #endif
    }
}
