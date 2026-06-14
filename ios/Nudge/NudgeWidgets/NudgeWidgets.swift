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

struct NudgeEntry: TimelineEntry {
    let date: Date
    let overdue: Int
    let todayDone: Int
    let todayTotal: Int
    let items: [WItem]

    static let sample = NudgeEntry(
        date: .now, overdue: 3, todayDone: 2, todayTotal: 5,
        items: [
            WItem(id: "1", title: "Pay rent", due: .now, hasTime: true, overdue: true, color: "E85D4A"),
            WItem(id: "2", title: "Call mum", due: .now.addingTimeInterval(7200), hasTime: true, overdue: false, color: "5B4FCF"),
            WItem(id: "3", title: "Go for a run", due: .now.addingTimeInterval(20000), hasTime: true, overdue: false, color: "7CA982")
        ])
    static let empty = NudgeEntry(date: .now, overdue: 0, todayDone: 0, todayTotal: 0, items: [])
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
        guard let data = await NudgeFeed.fetch() else { return .empty }
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
                          todayTotal: todayDone + todayOpen, items: Array(items.prefix(8)))
    }
}

// MARK: - Overdue (small)

struct OverdueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeOverdue", provider: NudgeProvider()) { e in
            VStack(alignment: .leading, spacing: 2) {
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
                    Circle().trim(from: 0, to: max(0.001, frac))
                        .stroke(WTheme.grad, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if e.todayTotal == 0 {
                        Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(WTheme.sage)
                    } else {
                        Text("\(e.todayDone)/\(e.todayTotal)").font(.system(.title3, design: .rounded).weight(.bold))
                    }
                }
                Text("today").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NudgeToday", provider: NudgeProvider()) { e in
            TodayWidgetView(entry: e)
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
    private var maxRows: Int { family == .systemLarge ? 7 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
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
            if entry.items.isEmpty {
                Spacer()
                HStack { Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(WTheme.sage)
                        Text("All clear").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Spacer() }
                Spacer()
            } else {
                ForEach(entry.items.prefix(maxRows)) { it in
                    HStack(spacing: 9) {
                        Circle().fill(it.overdue ? WTheme.coral : Color(wHex: it.color)).frame(width: 8, height: 8)
                        Text(it.title).font(.subheadline).lineLimit(1)
                        Spacer(minLength: 6)
                        if let d = it.due {
                            Text(wDueLabel(d, hasTime: it.hasTime))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(it.overdue ? WTheme.coral : .secondary)
                        }
                    }
                }
                if entry.items.count > maxRows {
                    Text("+\(entry.items.count - maxRows) more")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        #endif
    }
}
