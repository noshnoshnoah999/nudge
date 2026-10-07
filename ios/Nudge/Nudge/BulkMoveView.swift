// BulkMoveView.swift — Nudge (iOS)
// Bulk-move sheet for multi-select on Today/Overdue. Every selected reminder gets its
// own target date (defaulted to a shared "move all to" date you pick first, but each
// row can be dragged to a different day independently — e.g. some tomorrow, some next
// week, in one action).
//
// TIMES — three modes (2026-10-07):
//   • Keep own times   — only the date changes (the original behaviour).
//   • One time for all — every reminder moves to a single shared time.
//   • Set each         — every row gets its own time picker.
//
// AUTO-ARRANGE (2026-10-07): one button spaces the reminders being moved so none of them
// share a time with each other OR with reminders already on the target day. Rules (Noah's):
//   • window 07:45 – 19:30, 15 minutes apart, current (on-screen) order kept
//   • calendar events are ignored
//   • result is shown as a PREVIEW first; accepting fills the "Set each" times (and any
//     changed days) into the form, and Move still applies them
//   • if they don't all fit in a day: ask — "Squeeze in" (shrink the gap until they fit
//     inside the window) or "Spill to next day" (the extras go to the next day from 07:45,
//     avoiding that day's reminders, and onward if needed)
// The planning is a pure function (AutoArranger) so it can be reasoned about on its own.

import SwiftUI

struct BulkMoveView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let reminders: [Reminder]

    enum TimeMode: String, CaseIterable, Identifiable {
        case keep = "Keep times", one = "One time", each = "Set each"
        var id: String { rawValue }
    }

    /// Per-reminder target date. Seeded from `sharedDate` on appear, then editable
    /// independently — this is what lets some reminders move to tomorrow and others
    /// to next week in the same action.
    @State private var targetDates: [String: Date] = [:]
    /// Per-reminder time-of-day, used in "Set each" mode. Only hour/minute are read.
    @State private var targetTimes: [String: Date] = [:]
    @State private var sharedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var timeMode: TimeMode = .keep
    @State private var sharedTime = Date()
    @State private var showConflictWarning = false

    // Auto-arrange state
    @State private var arrangePreview: ArrangePreview?
    @State private var showOverflowChoice = false
    @State private var overflowCount = 0
    /// True while the current times are exactly what auto-arrange produced. Calendar
    /// clashes are deliberately ignored for those (Noah: overlapping calendar events is
    /// fine for auto-arranged times). Any manual time/date edit clears it.
    @State private var timesFromAutoArrange = false

    private var sortedReminders: [Reminder] {
        reminders.sorted { (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Moving \(reminders.count) reminder\(reminders.count == 1 ? "" : "s")")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)

                    // Move-all-to-this-day picker — applies to every row that hasn't been
                    // individually overridden below.
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MOVE ALL TO").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent)
                        DatePicker("", selection: $sharedDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical).tint(Theme.controlTint).labelsHidden()
                            .onChange(of: sharedDate) { _, newDate in
                                applySharedDateToAll(newDate)
                            }

                        // A manual mode change means the times are no longer auto-arranged.
                        // Done in the binding (not onChange) so acceptPreview can set
                        // timeMode = .each without clearing the flag it sets right after.
                        Picker("Times", selection: Binding(
                            get: { timeMode },
                            set: { m in withAnimation(Theme.spring) { timeMode = m }; timesFromAutoArrange = false }
                        )) {
                            ForEach(TimeMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        switch timeMode {
                        case .keep:
                            Text("Each reminder keeps its own time — only the date changes.")
                                .font(.caption).foregroundStyle(Theme.textMeta)
                        case .one:
                            DatePicker("", selection: $sharedTime, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                            Text("Every reminder below moves to this time.")
                                .font(.caption).foregroundStyle(Theme.textMeta)
                        case .each:
                            Text("Pick a time for each reminder below.")
                                .font(.caption).foregroundStyle(Theme.textMeta)
                        }

                        Button { runAutoArrange() } label: {
                            Label("Auto-arrange times", systemImage: "wand.and.stars")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        Text("Spaces them 15 min apart between 7:45 and 19:30, in this order, avoiding reminders already on that day. You'll see a preview first.")
                            .font(.caption).foregroundStyle(Theme.textMeta)
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius(16), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius(16), style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))

                    // Per-reminder overrides — each defaults to the shared date above, but can
                    // be pulled to a different day without affecting the others.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("REMINDERS").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                        ForEach(sortedReminders) { r in
                            reminderRow(r)
                        }
                    }

                    Button {
                        confirmAndApply()
                    } label: {
                        Text("Move \(reminders.count) Reminder\(reminders.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.bold)).foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Move Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                for r in reminders {
                    targetDates[r.id] = sharedDate
                    targetTimes[r.id] = originalTimeOfDay(r)
                }
            }
            .alert("Some reminders clash with your calendar", isPresented: $showConflictWarning) {
                Button("Move anyway", role: .destructive) { applyAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("One or more of the new times overlaps an existing calendar event.")
            }
            .alert("\(overflowCount) reminder\(overflowCount == 1 ? "" : "s") won't fit", isPresented: $showOverflowChoice) {
                Button("Squeeze in") { buildPreview(overflow: .squeeze) }
                Button("Spill to next day") { buildPreview(overflow: .spill) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("At 15 minutes apart they don't all fit between 7:45 and 19:30. Squeeze in shortens the gap so everything fits that day. Spill to next day moves the extras to the next day from 7:45.")
            }
            .sheet(item: $arrangePreview) { p in
                ArrangePreviewSheet(preview: p, titleFor: { id in
                    reminders.first { $0.id == id }.map { displayTitle($0) } ?? ""
                }, onAccept: { acceptPreview(p) })
            }
        }
        .tint(Theme.controlTint)
        .presentationBackground(Theme.bg)
    }

    private func reminderRow(_ r: Reminder) -> some View {
        let dateBinding = Binding<Date>(
            get: { targetDates[r.id] ?? sharedDate },
            set: { targetDates[r.id] = $0; touchedIds.insert(r.id); timesFromAutoArrange = false }
        )
        let timeBinding = Binding<Date>(
            get: { targetTimes[r.id] ?? originalTimeOfDay(r) },
            set: { targetTimes[r.id] = $0; timesFromAutoArrange = false }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(r)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                        .lineLimit(1)
                    if let lbl = dueLabel(r) {
                        Text("Currently \(lbl)").font(.caption).foregroundStyle(Theme.textMeta)
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) {
                DatePicker("", selection: dateBinding, displayedComponents: [.date])
                    .datePickerStyle(.compact).labelsHidden()
                    .tint(Theme.controlTint)
                if timeMode == .each {
                    DatePicker("", selection: timeBinding, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact).labelsHidden()
                        .tint(Theme.controlTint)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Theme.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous))
    }

    /// Re-seed every row the user hasn't individually overridden — a naive "set every
    /// row" would also stomp on a per-reminder date the user just deliberately picked.
    private func applySharedDateToAll(_ newDate: Date) {
        for r in reminders where !touchedIds.contains(r.id) {
            targetDates[r.id] = newDate
        }
        timesFromAutoArrange = false
    }

    /// Reminders whose date the user has explicitly changed away from the shared date —
    /// tracked so the shared-date picker doesn't clobber a deliberate per-row override.
    @State private var touchedIds: Set<String> = []

    /// The reminder's current time-of-day as a Date today (only hour/minute matter);
    /// 9:00 for undated reminders — the same fallback finalDate always used.
    private func originalTimeOfDay(_ r: Reminder) -> Date {
        let cal = Calendar.current
        let comps = parseDate(r.dueDate).map { cal.dateComponents([.hour, .minute], from: $0) }
        return cal.date(bySettingHour: comps?.hour ?? 9, minute: comps?.minute ?? 0, second: 0, of: Date()) ?? Date()
    }

    /// Compute the final date+time for a reminder given the current time mode.
    private func finalDate(for r: Reminder) -> Date {
        let day = targetDates[r.id] ?? sharedDate
        let cal = Calendar.current
        let source: Date
        switch timeMode {
        case .keep: source = originalTimeOfDay(r)
        case .one:  source = sharedTime
        case .each: source = targetTimes[r.id] ?? originalTimeOfDay(r)
        }
        let t = cal.dateComponents([.hour, .minute], from: source)
        return cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private func confirmAndApply() {
        // Auto-arranged times skip the calendar check by design (see timesFromAutoArrange).
        let hasConflict = !timesFromAutoArrange && reminders.contains { r in
            CalendarService.shared.conflictDescription(at: finalDate(for: r)) != nil
        }
        if hasConflict {
            showConflictWarning = true
        } else {
            applyAll()
        }
    }

    private func applyAll() {
        for r in reminders {
            store.reschedule(r.id, to: finalDate(for: r))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    // MARK: - Auto-arrange

    /// Minutes-from-midnight of every OTHER open reminder on `day` (not one being moved).
    private func existingMinutes(on day: Date) -> [Int] {
        let cal = Calendar.current
        let moving = Set(reminders.map(\.id))
        return store.open().compactMap { r in
            guard !moving.contains(r.id), let d = parseDate(r.dueDate), cal.isDate(d, inSameDayAs: day) else { return nil }
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    private func arrangeInput() -> [AutoArranger.Item] {
        let cal = Calendar.current
        return sortedReminders.map { r in
            AutoArranger.Item(id: r.id, day: cal.startOfDay(for: targetDates[r.id] ?? sharedDate))
        }
    }

    private func runAutoArrange() {
        let plan = AutoArranger.plan(items: arrangeInput(), overflow: .report, existing: existingMinutes(on:))
        if plan.overflowCount > 0 {
            overflowCount = plan.overflowCount
            showOverflowChoice = true
        } else {
            arrangePreview = ArrangePreview(placements: plan.placements, note: nil)
        }
    }

    private func buildPreview(overflow: AutoArranger.Overflow) {
        let plan = AutoArranger.plan(items: arrangeInput(), overflow: overflow, existing: existingMinutes(on:))
        var note: String? = nil
        if overflow == .squeeze, let g = plan.squeezedGap {
            note = g >= 15 ? nil : "Squeezed to \(g) minute\(g == 1 ? "" : "s") apart."
            if plan.squeezeOverlapsExisting {
                note = "Too many to fit even 1 minute apart without touching existing reminders, so some share times with reminders already on that day."
            }
        }
        arrangePreview = ArrangePreview(placements: plan.placements, note: note)
    }

    private func acceptPreview(_ p: ArrangePreview) {
        let cal = Calendar.current
        for pl in p.placements {
            targetDates[pl.id] = pl.day
            // A day that differs from the shared date (spilled, or a per-row override) must
            // survive a later change of the shared date.
            if !cal.isDate(pl.day, inSameDayAs: sharedDate) { touchedIds.insert(pl.id) }
            targetTimes[pl.id] = cal.date(bySettingHour: pl.minute / 60, minute: pl.minute % 60, second: 0, of: Date()) ?? Date()
        }
        withAnimation(Theme.spring) { timeMode = .each }
        timesFromAutoArrange = true
        arrangePreview = nil
    }
}

// MARK: - Preview

struct ArrangePreview: Identifiable {
    let id = UUID()
    let placements: [AutoArranger.Placement]
    let note: String?
}

private struct ArrangePreviewSheet: View {
    let preview: ArrangePreview
    let titleFor: (String) -> String
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let note = preview.note {
                    Section { Text(note).font(.footnote).foregroundStyle(Theme.textMeta) }
                }
                let byDay = Dictionary(grouping: preview.placements, by: \.day)
                ForEach(byDay.keys.sorted(), id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) {
                        ForEach(byDay[day] ?? [], id: \.id) { pl in
                            HStack {
                                Text(String(format: "%02d:%02d", pl.minute / 60, pl.minute % 60))
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 54, alignment: .leading)
                                Text(titleFor(pl.id)).font(.subheadline).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Auto-arrange preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Use these times") { onAccept() }.bold() }
            }
        }
        .tint(Theme.controlTint)
    }
}

// MARK: - Planner (pure)

/// Pure scheduling logic for auto-arrange. Times are minutes from midnight.
/// A slot at minute s "clashes" with a time t when |s − t| < gap — i.e. every reminder is
/// treated as owning `gap` minutes, so 15-minute spacing means nothing lands within 15
/// minutes of anything else, before or after.
enum AutoArranger {
    static let windowStart = 7 * 60 + 45   // 07:45
    static let windowEnd   = 19 * 60 + 30  // 19:30 (last allowed start)
    static let gap = 15
    static let maxSpillDays = 14

    enum Overflow { case report, squeeze, spill }

    struct Item { let id: String; let day: Date }   // day = start of the target day
    struct Placement { let id: String; let day: Date; let minute: Int }

    struct Plan {
        var placements: [Placement] = []
        var overflowCount = 0            // .report only: how many didn't fit
        var squeezedGap: Int? = nil      // .squeeze only: smallest gap used across days
        var squeezeOverlapsExisting = false
    }

    /// Greedy, order-preserving: each item takes the earliest start ≥ the previous item's
    /// start + gap that doesn't clash with anything already on the day. Returns the minutes
    /// placed (in order) and how many didn't fit before windowEnd.
    static func fill(count: Int, occupied: [Int], gap: Int) -> (placed: [Int], unplaced: Int) {
        var taken = occupied
        var placed: [Int] = []
        var cursor = windowStart
        for _ in 0..<count {
            var s = cursor
            // Jump past any clash; terminates because each jump strictly increases s.
            while let t = taken.first(where: { abs(s - $0) < gap }) { s = t + gap }
            if s > windowEnd { break }
            placed.append(s); taken.append(s); cursor = s + gap
        }
        return (placed, count - placed.count)
    }

    static func plan(items: [Item], overflow: Overflow, existing: (Date) -> [Int]) -> Plan {
        var out = Plan()
        let cal = Calendar.current
        // Group by day, keeping the given order within each day.
        var days: [Date] = []
        var byDay: [Date: [String]] = [:]
        for it in items {
            if byDay[it.day] == nil { days.append(it.day) }
            byDay[it.day, default: []].append(it.id)
        }
        days.sort()

        switch overflow {
        case .report:
            for d in days {
                let ids = byDay[d] ?? []
                let r = fill(count: ids.count, occupied: existing(d), gap: gap)
                out.overflowCount += r.unplaced
                for (i, m) in r.placed.enumerated() { out.placements.append(Placement(id: ids[i], day: d, minute: m)) }
            }

        case .squeeze:
            for d in days {
                let ids = byDay[d] ?? []
                let occ = existing(d)
                var used: [Int]? = nil
                var g = gap
                while g >= 1 {
                    let r = fill(count: ids.count, occupied: occ, gap: g)
                    if r.unplaced == 0 { used = r.placed; break }
                    g -= 1
                }
                if used == nil {
                    // Can't fit even 1 minute apart around existing reminders: ignore the
                    // existing ones and spread evenly across the window instead.
                    out.squeezeOverlapsExisting = true
                    g = max(1, (windowEnd - windowStart) / max(1, ids.count - 1))
                    used = fill(count: ids.count, occupied: [], gap: g).placed
                }
                out.squeezedGap = min(out.squeezedGap ?? g, g)
                for (i, m) in (used ?? []).enumerated() where i < ids.count {
                    out.placements.append(Placement(id: ids[i], day: d, minute: m))
                }
            }

        case .spill:
            // Walk forward day by day. Each day's queue = items spilled from the previous
            // day (they come first — they were earlier in the order) + that day's own items.
            // Items placed earlier in this run count as occupied on their day.
            var placedOn: [Date: [Int]] = [:]
            var carry: [String] = []
            var day = days.first ?? cal.startOfDay(for: Date())
            let lastOwnDay = days.last ?? day
            var spillDays = 0
            while true {
                let queue = carry + (byDay[day] ?? [])
                if !queue.isEmpty {
                    let r = fill(count: queue.count, occupied: existing(day) + (placedOn[day] ?? []), gap: gap)
                    for (i, m) in r.placed.enumerated() {
                        out.placements.append(Placement(id: queue[i], day: day, minute: m))
                        placedOn[day, default: []].append(m)
                    }
                    carry = Array(queue.suffix(r.unplaced))
                } else {
                    carry = []
                }
                if day >= lastOwnDay && carry.isEmpty { break }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                if day >= lastOwnDay { spillDays += 1 }
                if spillDays > maxSpillDays {
                    // Pathological (hundreds of reminders): stop spilling; leave the rest at
                    // their own day's window start rather than looping forever.
                    for id in carry { out.placements.append(Placement(id: id, day: day, minute: windowStart)) }
                    break
                }
                day = next
            }
        }
        return out
    }
}
