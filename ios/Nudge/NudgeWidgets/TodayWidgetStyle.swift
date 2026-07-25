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
    var backgroundColor: Color?   // nil = system default widget background material

    static let `default` = TodayStyle(design: .default, titleSize: CGFloat(widgetFontSizeDefault),
                                      rowSpacing: 9, grayscale: false, backgroundColor: nil)

    init(design: Font.Design, titleSize: CGFloat, rowSpacing: CGFloat, grayscale: Bool, backgroundColor: Color? = nil) {
        self.design = design; self.titleSize = titleSize
        self.rowSpacing = rowSpacing; self.grayscale = grayscale
        self.backgroundColor = backgroundColor
    }

    init(_ c: TodayWidgetConfigIntent) {
        design = c.font.design
        // Clamp defensively in case an old config stored an out-of-range value.
        titleSize = CGFloat(min(max(c.fontSize, widgetFontSizeRange.lowerBound), widgetFontSizeRange.upperBound))
        rowSpacing = c.spacing.rowSpacing
        grayscale = c.grayscale
        backgroundColor = c.background.color
    }
}
