// NudgeWidgets.swift — Nudge widget extension
// Home-screen widgets (overdue, progress, today list, quick-add) + the bundle
// that also registers the Control Center control.

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct WItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
    let hasTime: Bool
    let overdue: Bool
    let color: String
}

/// Whether the timeline entry reflects real fetched data or a failed sync.
/// This is what lets the widget tell "genuinely nothing due" apart from
/// "couldn't reach your reminders" — the two used to look identical ("All clear").
enum WLoadState {
    case loaded   // fetch succeeded; items/counts are real (may legitimately be empty)
    case failed   // fetch returned nil (signed out, expired token, or network) — data unknown
}

struct NudgeEntry: TimelineEntry {
    let date: Date
    let overdue: Int
    let todayDone: Int
    let todayTotal: Int
    let items: [WItem]
    // Defaults to .loaded so existing initialisers (samples/placeholders) stay valid.
    var state: WLoadState = .loaded

    static let sample = NudgeEntry(
        date: .now, overdue: 3, todayDone: 2, todayTotal: 5,
        items: [
            WItem(id: "1", title: "Pay rent", due: .now, hasTime: true, overdue: true, color: "E85D4A"),
            WItem(id: "2", title: "Call mum", due: .now.addingTimeInterval(7200), hasTime: true, overdue: false, color: "5B4FCF"),
            WItem(id: "3", title: "Go for a run", due: .now.addingTimeInterval(20000), hasTime: true, overdue: false, color: "7CA982")
        ])
    // A genuine empty result: fetch worked, nothing due. Shows "All clear".
    static let empty = NudgeEntry(date: .now, overdue: 0, todayDone: 0, todayTotal: 0, items: [], state: .loaded)
    // A failed fetch: data unknown. Shows "Can't sync — open Nudge", never "All clear".
    static let failed = NudgeEntry(date: .now, overdue: 0, todayDone: 0, todayTotal: 0, items: [], state: .failed)
}

struct NudgeProvider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (NudgeEntry) -> Void) {
        Task { completion(await Self.build()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeEntry>) -> Void) {
        Task {
            let entry = await Self.build()
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    static func build() async -> NudgeEntry {
        // A nil fetch means the widget couldn't reach the user's data (signed out,
        // expired token, or network) — NOT that there's nothing due. Return .failed
        // so the view shows "Can't sync — open Nudge" instead of a false "All clear".
        // Only a successful fetch that genuinely yields zero items shows "All clear".
        guard let data = await NudgeFeed.fetch() else { return .failed }
        let now = Date(); let cal = Calendar.current
        func color(_ id: String?) -> String { data.lists.first { $0.id == (id ?? "reminders") }?.color ?? "5B4FCF" }
        func open(_ r: WReminder) -> Bool { !(r.completed ?? false) && !(r.dismissed ?? false) }
        func snoozed(_ r: WReminder) -> Bool { if let s = wParseDate(r.snoozedUntil) { return s > now }; return false }

        var overdue = 0, todayDone = 0, todayOpen = 0
        var items: [WItem] = []
        for r in data.reminders {
            // Today progress — mirror the app's todayStats exactly: done = completed today;
            // the total also counts open items DUE today even if their time has already
            // passed. (The widget used to drop those via !isOver, so late at night it read
            // 11/11 instead of the app's 11/17.)
            if let ca = wParseDate(r.completedAt), cal.isDateInToday(ca) { todayDone += 1 }
            else if !(r.completed ?? false), let dd = wParseDate(r.dueDate), cal.isDateInToday(dd) { todayOpen += 1 }

            // Overdue count + the items list keep their own open/not-snoozed logic.
            guard open(r), !snoozed(r), let d = wParseDate(r.dueDate) else { continue }
            let isOver = d < now
            if isOver { overdue += 1 }
            if isOver || cal.isDateInToday(d) {
                items.append(WItem(id: r.id, title: wDisplay(r.title), due: d,
                                   hasTime: r.hasTime ?? false, overdue: isOver, color: color(r.listId)))
            }
        }
        items.sort { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        return NudgeEntry(date: now, overdue: overdue, todayDone: todayDone,
                          todayTotal: todayDone + todayOpen, items: Array(items.prefix(8)),
                          state: .loaded)
    }
}

// MARK: - Overdue (small)

struct OverdueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeOverdue", provider: NudgeProvider()) { e in
            VStack(alignment: .leading, spacing: 2) {
                if e.state == .failed {
                    // Failed fetch — don't claim "all clear" with a big 0. Show a neutral
                    // can't-sync state so a stale/expired token never reads as "0 overdue".
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text("—")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("can't sync")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: e.overdue > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.title3).foregroundStyle(e.overdue > 0 ? WTheme.coral : WTheme.sage)
                    Spacer()
                    Text("\(e.overdue)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(e.overdue > 0 ? WTheme.coral : WTheme.sage)
                        .contentTransition(.numericText())
                    Text(e.overdue == 0 ? "all clear" : e.overdue == 1 ? "overdue" : "overdue")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Overdue")
        .description("How many reminders are overdue.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Progress ring (small)

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeProgress", provider: NudgeProvider()) { e in
            let frac = e.todayTotal > 0 ? Double(e.todayDone) / Double(e.todayTotal) : (e.todayDone > 0 ? 1 : 0)
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 9)
                    if e.state == .failed {
                        // Failed fetch — show a neutral sync glyph, not a full "done" ring,
                        // so an empty result from a bad token doesn't look like 0/0 complete.
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.headline.bold()).foregroundStyle(.secondary)
                    } else {
                        Circle().trim(from: 0, to: max(0.001, frac))
                            .stroke(WTheme.grad, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if e.todayTotal == 0 {
                            Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(WTheme.sage)
                        } else {
                            Text("\(e.todayDone)/\(e.todayTotal)").font(.system(.title3, design: .rounded).weight(.bold))
                        }
                    }
                }
                Text(e.state == .failed ? "can't sync" : "today")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today's Progress")
        .description("How much of today you've cleared.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Quick add (small, interactive)

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeQuickAdd", provider: NudgeProvider()) { _ in
            Button(intent: QuickAddReminderIntent()) {
                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(WTheme.grad, in: Circle())
                    Text("Add reminder").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Tap to add a reminder.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Quick add (Lock Screen accessory)

/// Lock Screen / accessory widget: one tap opens Nudge straight into the New
/// Reminder sheet. Uses `widgetURL` (not an interactive intent) because on the
/// Lock Screen a tap launches the app via the widget's URL — WidgetKit delivers
/// it to the app's `onOpenURL`. Circular for round slots, rectangular for wide.
struct QuickAddLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeQuickAddLock", provider: NudgeProvider()) { _ in
            QuickAddLockView()
        }
        .configurationDisplayName("Add to Nudge")
        .description("One tap on your Lock Screen to capture a reminder.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct QuickAddLockView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                }
            default:   // .accessoryRectangular
                HStack(spacing: 9) {
                    Image(systemName: "bell.badge.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add to Nudge").font(.headline)
                        Text("Tap to capture").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(URL(string: "nudge://quickadd"))
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Today list (medium + large)

/// Timeline entry that also carries the user's chosen style. The Today widget uses an
/// AppIntentConfiguration so the style is picked in Edit mode (no App Group needed).
struct TodayConfigEntry: TimelineEntry {
    let base: NudgeEntry
    let style: TodayStyle
    var date: Date { base.date }
}

/// AppIntent-configured provider: same data as NudgeProvider, plus the config's style.
struct TodayConfigProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayConfigEntry {
        TodayConfigEntry(base: .sample, style: .default)
    }
    func snapshot(for configuration: TodayWidgetConfigIntent, in context: Context) async -> TodayConfigEntry {
        TodayConfigEntry(base: await NudgeProvider.build(), style: TodayStyle(configuration))
    }
    func timeline(for configuration: TodayWidgetConfigIntent, in context: Context) async -> Timeline<TodayConfigEntry> {
        let entry = TodayConfigEntry(base: await NudgeProvider.build(), style: TodayStyle(configuration))
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NudgeToday",
                               intent: TodayWidgetConfigIntent.self,
                               provider: TodayConfigProvider()) { e in
            // BACKGROUND IS DRAWN AS CONTENT, NOT AS `containerBackground`.
            //
            // Three attempts, all verified on Noah's device, established why:
            //   1. `containerBackground(Color)`                    → card rendered #181818
            //   2. + `containerBackgroundRemovable(false)`         → still #181818
            //   3. + Image with `.widgetAccentedRenderingMode(.fullColor)` → still #181818
            //
            // Attempt 3 rules out the "Color can't hold its colour, Image can" theory: an
            // image in the container background got overridden too. The conclusion is that in
            // Apple's tinted Home Screen mode (`.accented`) the system overrides the container
            // background layer regardless of what's inside it.
            //
            // Content, however, is drawn ON TOP of the container background and is not
            // substituted. So the background moves into the content layer as the bottom of a
            // ZStack. Whatever grey the system puts behind us, an opaque content layer covers it.
            //
            // `.contentMarginsDisabled()` (below) is required — without it WidgetKit insets the
            // content and the system's grey would still show as a border around our background.
            // That also means the padding WidgetKit used to supply must now be applied by hand.
            //
            // USE `.background { }`, NOT A `ZStack`.
            // The first version of this used `ZStack { background; content }` with
            // `.ignoresSafeArea()` on the background. That broke layout on-device: the list
            // rendered ABOVE the widget's top edge with its first rows clipped off-screen.
            // Cause — `ignoresSafeArea()` expands that child beyond the widget's bounds, which
            // enlarges the ZStack's layout region, and the ZStack's default `.center` alignment
            // then positioned the content relative to the enlarged region instead of the visible
            // one. The overflow at the bottom was the list's invisible trailing `Spacer`, so it
            // looked like "only one reminder is showing" rather than like a shifted layout.
            //
            // `.background { }` cannot cause that: it draws behind the content, sized to the
            // content's own frame, and takes no part in layout. The explicit
            // `.frame(maxWidth:maxHeight:alignment:.topLeading)` is what makes the content fill
            // the widget and stay pinned to the top, so the background fills it too.
            TodayWidgetView(entry: e.base, style: e.style)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { TodayWidgetBackground(background: e.style.background) }
            // Keep the ordinary system background for the "System Default" preset. When a
            // near-black preset is chosen, TodayWidgetBackground paints over this anyway.
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today & Overdue")
        .description("Your next reminders at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
        // Required so our content background reaches the widget's edges. See the ZStack note.
        .contentMarginsDisabled()
        //
        // NOTE: `containerBackgroundRemovable(false)` was deliberately REMOVED here.
        // It was added in 88c1a88 to stop the container background being stripped, but it
        // never fixed the colour, and it carries a documented side effect (Apple Developer
        // Forums 768862) where content gets pulled into the tint treatment even when marked
        // non-accentable — a real risk of black-on-black titles given Noah's near-black tint.
        // Now that the background is content rather than container background, nothing depends
        // on that modifier, so the risk isn't worth carrying.
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NudgeEntry
    var style: TodayStyle = .default
    /// How many rows actually fit in `height` points.
    ///
    /// Measured from real geometry rather than guessed. The previous version hardcoded the
    /// usable height (320pt large / 130pt medium) AND computed a row as
    /// `titleSize + rowSpacing` — but a row is really `titleSize * 1.15` tall (see
    /// `WidgetRowTitle`'s `.frame(height:)`) plus the spacing. Both errors pushed the same
    /// way, so it consistently thought more rows fit than actually did, and with a large font
    /// the list overflowed the widget.
    private func rowLimit(for height: CGFloat) -> Int {
        let rowHeight = style.titleSize * 1.15 + style.rowSpacing
        guard rowHeight > 0, height > 0 else { return 1 }
        // + rowSpacing because N rows have only N-1 gaps between them, so the last row
        // doesn't need trailing spacing to fit.
        let fit = Int((height + style.rowSpacing) / rowHeight)
        return max(1, min(fit, family == .systemLarge ? 8 : 3))
    }

    var body: some View {
        // GeometryReader supplies the real content height, so the row count is derived from
        // actual available space instead of hardcoded per-family guesses. It fills whatever
        // it's offered and aligns its child top-leading, which is exactly what's wanted here.
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: style.rowSpacing) {
                // Header ("Today" title + overdue pill) removed — pure Dumb-Phone list, no chrome.
                // The pill also rendered as a grey blob in Apple's tinted home-screen mode, which
                // is another reason to drop it. Failed/empty states below are unaffected.
                if entry.state == .failed {
                    // Couldn't reach the user's data (signed out / expired token / network).
                    // Show an honest, actionable state — NEVER a misleading "All clear".
                    // Tapping opens Nudge, which refreshes the token so the next widget
                    // timeline can fetch successfully.
                    Spacer()
                    // "nudgeapp://open" is handled in NudgeApp.onOpenURL: any host other than
                    // "add" just brings the app to the front, which refreshes the auth token.
                    Link(destination: URL(string: "nudgeapp://open")!) {
                        HStack { Spacer()
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title).foregroundStyle(.secondary)
                                Text("Can't sync").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                Text("Open Nudge").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer() }
                    }
                    Spacer()
                } else if entry.items.isEmpty {
                    // Genuine empty result: fetch succeeded, nothing due today. This is the
                    // only case that should ever read "All clear".
                    Spacer()
                    HStack { Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(WTheme.sage)
                            Text("All clear").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Spacer() }
                    Spacer()
                } else {
                    // Dumb-Phone style list: each row is just the reminder title — lowercase, bold,
                    // left-aligned, big — like an app-launcher. No ring, no due label. Tapping the
                    // text completes the reminder (writes straight to Supabase; no app launch).
                    // Recurring reminders complete here too, but their next occurrence is spawned
                    // when the app next opens (see CompleteReminderWidgetIntent).
                    ForEach(entry.items.prefix(rowLimit(for: geo.size.height))) { it in
                        Button(intent: CompleteReminderWidgetIntent(reminderId: it.id)) {
                            WidgetRowTitle(title: it.title.lowercased(),
                                           size: style.titleSize, design: style.design)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Never let the list paint outside the widget, whatever the font size. Belt-and-braces
            // after the overflow bug where rows rendered above the widget's top edge.
            .clipped()
        }
        // Grayscale toggle (dumb-phone look). Note: Apple "tinted" home-screen mode already
        // strips colour, so this only visibly changes things in full-colour mode.
        .grayscale(style.grayscale ? 1 : 0)
    }
}

/// One reminder title, hard-cut on the right with NO ellipsis and NO chance of
/// left/centre spill.
///
/// History: two earlier fixes used `.fixedSize(horizontal: true)` + `.clipped()`.
/// Both failed on-device — `.fixedSize` lets the text ignore the frame width, and
/// inside WidgetKit the clip landed symmetrically, slicing BOTH edges
/// ("...mp focus modes..."). No amount of reordering fixed it reliably.
///
/// This version is deterministic. `GeometryReader` gives the exact row width `w`.
/// The title is laid out at its natural width (single line, no truncation, so no
/// "…"), pinned to the leading edge, then MASKED by a solid rectangle exactly `w`
/// wide and leading-anchored. The mask is a concrete pixel rect — WidgetKit can't
/// reinterpret it the way it did the clip. Anything past the right edge is masked
/// away; nothing can appear left of x=0. Result: clean right-side cut, no ellipsis.
private struct WidgetRowTitle: View {
    let title: String
    let size: CGFloat
    let design: Font.Design

    var body: some View {
        // GeometryReader gives the exact row width as a concrete number. The title is
        // laid out at natural width (single line, no truncation → no "…"), pinned to the
        // leading edge, then masked by a Rectangle of that exact pixel width. A mask
        // clips to its own geometry, so overflow past the right edge is hidden and
        // nothing can appear left of x=0. Using an explicit width (not a Rectangle in an
        // HStack, which can collapse) is what makes this deterministic.
        GeometryReader { geo in
            Text(title)
                .font(.system(size: size, weight: .bold, design: design))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)        // natural width, no "…"
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .mask(
                    Rectangle()
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                )
        }
        .frame(height: size * 1.15)   // GeometryReader has no intrinsic height
        .contentShape(Rectangle())
    }
}

// MARK: - Bundle (@main): widgets + the Control Center control

@main
struct NudgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        OverdueWidget()
        ProgressWidget()
        QuickAddWidget()
        QuickAddLockWidget()
        TodayWidget()
        #if !targetEnvironment(macCatalyst)
        NudgeQuickAddControl()   // Control Centre controls are iOS-only
        if #available(iOS 26.0, *) { NudgeAlarmLiveActivity() }   // urgent-reminder alarm UI
        #endif
    }
}

// MARK: - Urgent-reminder alarm Live Activity (AlarmKit)

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import AlarmKit

@available(iOS 26.0, *)
struct NudgeAlarmLiveActivity: Widget {
    private func title(_ c: ActivityViewContext<NudgeAlarmAttributes>) -> String {
        c.attributes.metadata?.title ?? "Reminder"
    }
    /// Subtitle that mirrors Apple's: "Snooze 8:57 min" while counting down, else "Reminder".
    @ViewBuilder private func status(_ c: ActivityViewContext<NudgeAlarmAttributes>) -> some View {
        switch c.state.mode {
        case .countdown(let cd):
            HStack(spacing: 4) {
                Text("Snooze")
                Text(timerInterval: Date.now...cd.fireDate, countsDown: true)
                    .monospacedDigit()
            }
        case .paused:
            Text("Paused")
        default:
            Text("Reminder")
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NudgeAlarmAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "alarm.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    status(context).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(title(context)).font(.headline).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill").foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(title(context)).font(.headline).lineLimit(1)
                        status(context).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            } compactTrailing: {
                if case .countdown(let cd) = context.state.mode {
                    Text(timerInterval: Date.now...cd.fireDate, countsDown: true)
                        .monospacedDigit().frame(maxWidth: 44)
                } else {
                    Image(systemName: "bell.fill").foregroundStyle(.orange)
                }
            } minimal: {
                Image(systemName: "alarm.fill").foregroundStyle(.orange)
            }
        }
    }
}
#endif
