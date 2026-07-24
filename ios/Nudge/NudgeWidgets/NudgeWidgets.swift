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
            TodayWidgetView(entry: e.base, style: e.style)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today & Overdue")
        .description("Your next reminders at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NudgeEntry
    var style: TodayStyle = .default
    // Rows that fit depend on the chosen font size + spacing — big Dumb-Phone text means
    // fewer rows before overflow. Estimate from the widget's usable height so large text
    // doesn't spill out of the widget.
    private var maxRows: Int {
        let usableHeight: CGFloat = (family == .systemLarge ? 320 : 130)
        let rowHeight = style.titleSize + style.rowSpacing
        let fit = Int(usableHeight / max(rowHeight, 1))
        return max(1, min(fit, family == .systemLarge ? 8 : 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.rowSpacing) {
            HStack {
                Text("Today").font(.headline.weight(.bold))
                Spacer()
                if entry.overdue > 0 {
                    Text("\(entry.overdue) overdue")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(WTheme.coralGrad, in: Capsule())
                }
            }
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
                ForEach(entry.items.prefix(maxRows)) { it in
                    Button(intent: CompleteReminderWidgetIntent(reminderId: it.id)) {
                        // Clean cut-off with NO "…". The title renders at its natural width on one
                        // line (.fixedSize), then is anchored to the LEADING edge of a full-width
                        // frame BEFORE clipping. That ordering is the whole fix: the previous
                        // version wrapped the text in an HStack + Spacer, which let the oversized
                        // fixedSize text sit CENTRED, so .clipped() sliced BOTH edges (the
                        // "...mp focus modes..." bug). Anchoring leading before .clipped() pins the
                        // text to the left, so only the right overflow is sliced off — no ellipsis.
                        Text(it.title.lowercased())
                            .font(.system(size: style.titleSize, weight: .bold, design: style.design))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)     // natural width, no "…"
                            .frame(maxWidth: .infinity, alignment: .leading)  // pin left BEFORE clip
                            .clipped()                                        // slice overflow on the right
                            // .clipped() only affects drawing, not hit-testing — a long, fixedSize
                            // title can still report a tap target wider than the visible row (and
                            // wide enough to overlap the next row). Pin the tap target to the same
                            // bounds the row is actually drawn in.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Grayscale toggle (dumb-phone look). Note: Apple "tinted" home-screen mode already
        // strips colour, so this only visibly changes things in full-colour mode.
        .grayscale(style.grayscale ? 1 : 0)
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
