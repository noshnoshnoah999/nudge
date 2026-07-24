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
}

// MARK: - Resolved style passed into the view

/// A plain value bundling the resolved style so the view doesn't reach into the intent.
struct TodayStyle {
    var design: Font.Design
    var titleSize: CGFloat
    var rowSpacing: CGFloat
    var grayscale: Bool

    static let `default` = TodayStyle(design: .default, titleSize: CGFloat(widgetFontSizeDefault),
                                      rowSpacing: 9, grayscale: false)

    init(design: Font.Design, titleSize: CGFloat, rowSpacing: CGFloat, grayscale: Bool) {
        self.design = design; self.titleSize = titleSize
        self.rowSpacing = rowSpacing; self.grayscale = grayscale
    }

    init(_ c: TodayWidgetConfigIntent) {
        design = c.font.design
        // Clamp defensively in case an old config stored an out-of-range value.
        titleSize = CGFloat(min(max(c.fontSize, widgetFontSizeRange.lowerBound), widgetFontSizeRange.upperBound))
        rowSpacing = c.spacing.rowSpacing
        grayscale = c.grayscale
    }
}
