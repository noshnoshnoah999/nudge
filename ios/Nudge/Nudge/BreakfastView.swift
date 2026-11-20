// BreakfastView.swift — Nudge (iOS + Mac Catalyst)
// The Breakfast shopping list shared with Budget (see BreakfastSync.swift for the rules).
// Home card ("Breakfast · 6 of 15 bought") → this sheet: this week, then next week
// (collapsed). Unbought on top by shop; bought in a collapsed "Bought" list, each with its day.
// Tick and untick need two taps (the circle beats in between). Tick = bought today. Skip only explains that skipping
// happens in Budget and offers to open Budget at that week. No ¥ totals — Budget owns money.

import SwiftUI
import UIKit

// MARK: - Home card

struct BreakfastHomeCard: View {
    @ObservedObject private var store = BreakfastStore.shared
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "cart").font(.callout).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("BREAKFAST").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Theme.textMeta)
                    Text(summary).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textMeta)
            }
            .padding(.vertical, Theme.minimal ? 12 : 14)
            .padding(.horizontal, Theme.minimal ? 0 : 16)
            .background(Theme.minimal ? Color.clear : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.radius(16), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius(16), style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private var summary: String {
        if let w = store.thisWeek {
            let left = w.rows.count - w.doneCount
            return left == 0 ? "All bought this week" : "\(w.doneCount) of \(w.rows.count) bought · \(left) left"
        }
        switch store.state {
        case .notSetUp: return "Not set up in Budget yet"
        case .never: return "Loading…"
        default:
            return store.lastFetched == nil ? "Can't reach Budget's list right now"
                                            : "Open Budget once this week to load the list"
        }
    }
}

// MARK: - Sheet

struct BreakfastView: View {
    @ObservedObject private var store = BreakfastStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showNext = false
    @State private var skipWeek: String?          // the week of the row whose Skip was tapped
    @State private var budgetMissing = false
    @State private var openBought: Set<String> = []   // weeks whose Bought list is open
    @State private var armedId: String?               // row waiting for its confirming 2nd tap
    @State private var armTimer: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusNote
                    let weeks = store.weeks
                    if weeks.isEmpty {
                        emptyState
                    } else {
                        ForEach(weeks) { w in weekSection(w) }
                    }
                }
                .padding(16)
            }
            .refreshable { await store.refresh() }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Breakfast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await store.refresh() }
            .alert("Skip in Budget", isPresented: Binding(get: { skipWeek != nil }, set: { if !$0 { skipWeek = nil } })) {
                if !budgetMissing, let w = skipWeek, BudgetLink.url(week: w) != nil {
                    Button("Open Budget") { if let w = skipWeek { BudgetLink.open(week: w) } }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Skips change your breakfast money, so do this in Budget.")
            }
        }
        .tint(Theme.controlTint)
        .presentationBackground(Theme.bg)
    }

    // MARK: Sections

    @ViewBuilder private var statusNote: some View {
        switch store.state {
        case .offline:
            note("wifi.slash", store.lastFetched == nil
                 ? "Can't reach Budget's list right now."
                 : "Offline — showing the list from \(store.lastFetched!.formatted(.dateTime.weekday(.abbreviated).hour().minute())). Ticks will send when you're back online.")
        case .notSetUp:
            note("exclamationmark.triangle", "Budget's shared list isn't set up yet.")
        default:
            EmptyView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cart").font(.largeTitle).foregroundStyle(Theme.accent)
            Text("No breakfast list yet").font(.headline).foregroundStyle(Theme.textMain)
            Text("Open Budget once this week and the list will appear here.")
                .font(.subheadline).foregroundStyle(Theme.textMeta).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 30)
    }

    @ViewBuilder private func weekSection(_ w: BreakfastWeek) -> some View {
        let isThis = w.monday <= BreakfastStore.dayKey()
        let expanded = isThis || showNext
        let open = w.rows.filter { !$0.isDone }
        let bought = Self.boughtNewestFirst(w.rows.filter(\.isDone))
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if !isThis { withAnimation(Theme.spring) { showNext.toggle() } }
            } label: {
                HStack(spacing: 7) {
                    Text("\(isThis ? "THIS WEEK" : "NEXT WEEK") · \(Self.range(w.monday).uppercased())")
                        .font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent)
                    if !isThis {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                    }
                    Spacer()
                    Text("\(w.doneCount) of \(w.rows.count)").font(.caption.weight(.semibold)).foregroundStyle(Theme.textMeta)
                        .contentTransition(.numericText())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isThis)

            if expanded {
                // Still to buy — on top, grouped by shop (Noah, 20 Nov 2026).
                if open.isEmpty {
                    Text("All bought").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.sage).padding(.leading, 2)
                } else {
                    ForEach(Self.byShop(open)) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.shop.isEmpty ? "Other" : g.shop)
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textMeta).padding(.leading, 2)
                            ForEach(g.rows) { row($0) }
                        }
                    }
                }
                // Bought — collapsed by default, newest day first, each with its own day.
                if !bought.isEmpty {
                    let isOpen = openBought.contains(w.monday)
                    Button {
                        withAnimation(Theme.spring) {
                            if isOpen { openBought.remove(w.monday) } else { openBought.insert(w.monday) }
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                            Text("BOUGHT").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                            Text("\(bought.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Theme.surfaceAlt, in: Capsule())
                            Spacer()
                        }
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isOpen { ForEach(bought) { row($0) } }
                }
            }
        }
    }

    private func row(_ r: BreakfastRow) -> some View {
        let armed = armedId == r.id
        return HStack(spacing: 12) {
            Button { tapCircle(r) } label: {
                HeartbeatCircle(done: r.isDone, armed: armed)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(r.isDone ? "Untick \(r.name)" : "Tick \(r.name)")
            .accessibilityHint(armed ? "Tap again to confirm" : "Tap twice to confirm")

            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(r)).font(.subheadline)
                    .foregroundStyle(r.isDone ? Theme.textMeta : Theme.textMain)
                    .strikethrough(r.isDone, color: Theme.textMeta.opacity(0.5))
                    .lineLimit(2)
                Text(armed ? (r.isDone ? "Tap again to untick" : "Tap again to tick") : Self.yen(r.price))
                    .font(.caption.weight(armed ? .semibold : .regular))
                    .foregroundStyle(armed ? Theme.accent : Theme.textMeta)
            }
            Spacer(minLength: 0)
            if r.isDone {
                Text(Self.boughtDay(r.done_on)).font(.caption.weight(.semibold)).foregroundStyle(Theme.sage)
            } else {
                Button("Skip") {
                    budgetMissing = !BudgetLink.isInstalled
                    skipWeek = r.week
                }
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    /// Two taps to tick or untick (Noah, 20 Nov 2026): the first tap arms the circle — it beats
    /// like a heartbeat for 3 s — and only a second tap on the SAME circle in that time acts.
    private func tapCircle(_ r: BreakfastRow) {
        if armedId == r.id {
            armTimer?.cancel()
            armedId = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(Theme.spring) { store.toggle(r) }
        } else {
            armTimer?.cancel()
            armedId = r.id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let id = r.id
            armTimer = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled, armedId == id { armedId = nil }
            }
        }
    }

    private func note(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(Theme.textMeta)
            Text(text).font(.caption).foregroundStyle(Theme.textMeta)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Formatting

    /// "Single Lemon (3 of 7)", "(3 of 3 · half)", or "(half)" for a half-quantity item.
    static func title(_ r: BreakfastRow) -> String {
        let half = r.size > 0 && r.size < 1
        let part = r.size == 0.5 ? "half" : String(format: "%g", r.size)
        if r.unit > 0 { return "\(r.name) (\(r.unit) of \(r.unit_of)\(half ? " · \(part)" : ""))" }
        return half ? "\(r.name) (\(part))" : r.name
    }

    static func yen(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.rounded() == v ? 0 : 1
        return "¥" + (f.string(from: NSNumber(value: v)) ?? "\(v)")
    }

    /// "Tue 17" for the day bought; "Bought" when Budget didn't record a day.
    static func boughtDay(_ key: String?) -> String {
        guard let key, let d = BreakfastStore.date(key) else { return "Bought" }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// "16–22 Nov", or "30 Nov – 6 Dec" across a month end.
    static func range(_ monday: String) -> String {
        guard let s = BreakfastStore.date(monday),
              let e = Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: s) else { return monday }
        let cal = Calendar(identifier: .gregorian)
        let sameMonth = cal.component(.month, from: s) == cal.component(.month, from: e)
        let day = DateFormatter(); day.dateFormat = "d"
        let dm = DateFormatter(); dm.dateFormat = "d MMM"
        return sameMonth ? "\(day.string(from: s))–\(dm.string(from: e))" : "\(dm.string(from: s)) – \(dm.string(from: e))"
    }

    /// Rows grouped by shop, shops in the order Budget lists their first item.
    /// Bought rows, newest day first; same day (or no day) keeps Budget's order.
    static func boughtNewestFirst(_ rows: [BreakfastRow]) -> [BreakfastRow] {
        rows.sorted { a, b in
            let da = a.done_on ?? "", db = b.done_on ?? ""
            if da != db { return da > db }
            return (a.sort, a.unit) < (b.sort, b.unit)
        }
    }

    struct ShopGroup: Identifiable { let shop: String; let rows: [BreakfastRow]; var id: String { shop } }
    static func byShop(_ rows: [BreakfastRow]) -> [ShopGroup] {
        var order: [String] = []
        var groups: [String: [BreakfastRow]] = [:]
        for r in rows {
            if groups[r.shop] == nil { order.append(r.shop) }
            groups[r.shop, default: []].append(r)
        }
        return order.map { ShopGroup(shop: $0, rows: groups[$0] ?? []) }
    }
}

// MARK: - Heartbeat circle

/// The tick circle. Armed (first tap done) -> it beats like a heart, a double "lub-dub" with a
/// rest, shown filled so it's obvious. The beat runs even in Minimal design, because it's the
/// only sign the first tap landed.
struct HeartbeatCircle: View {
    let done: Bool
    let armed: Bool

    var body: some View {
        let icon = armed ? (done ? "checkmark.circle" : "circle.inset.filled")
                         : (done ? "checkmark.circle.fill" : "circle")
        let base = Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent)
            .frame(width: 32, height: 32)
        if armed {
            base.phaseAnimator([1.0, 1.32, 1.0, 1.22, 1.0, 1.0]) { content, scale in
                content.scaleEffect(scale)
            } animation: { scale in
                scale == 1.0 ? .easeIn(duration: 0.14) : .easeOut(duration: 0.12)
            }
        } else {
            base
        }
    }
}

// MARK: - budget:// link

/// Opens the Budget app at a breakfast week. The week comes from the shared table, so it is
/// checked to be a real "YYYY-MM-DD" before it goes into a link.
enum BudgetLink {
    static func url(week: String) -> URL? {
        guard BreakfastStore.isDayKey(week) else { return nil }
        return URL(string: "budget://breakfast?week=\(week)")
    }
    /// Needs "budget" in LSApplicationQueriesSchemes (Info.plist).
    static var isInstalled: Bool {
        guard let u = URL(string: "budget://") else { return false }
        return UIApplication.shared.canOpenURL(u)
    }
    static func open(week: String) {
        guard let u = url(week: week) else { return }
        UIApplication.shared.open(u)
    }
}
