// BreakfastPlannerView.swift — Nudge (iOS + Mac Catalyst)
// "Remind me to buy" planner for the Breakfast list (Noah, 20 Nov 2026).
// What: everything still unbought that week, or picked items with a count each.
// When: date + time. Repeat: once (this week or next — the only weeks Budget publishes)
// or every week. Saves a normal reminder in the Breakfast list (BreakfastReminders.swift).

import SwiftUI

struct BreakfastPlannerView: View {
    @EnvironmentObject var nudge: NudgeStore
    @ObservedObject private var bs = BreakfastStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var everything: Bool
    @State private var counts: [String: Int]
    @State private var due: Date
    @State private var weekly = false

    init(preselectItem: String?) {
        _everything = State(initialValue: preselectItem == nil)
        _counts = State(initialValue: preselectItem.map { [$0: 1] } ?? [:])
        // Default: the next whole hour.
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        _due = State(initialValue: cal.date(bySetting: .minute, value: 0, of: next) ?? next)
    }

    /// One entry per Breakfast item, in Budget's order (from the published weeks).
    private struct Item: Identifiable { let id: String; let name: String; let perWeek: Int }

    private var catalog: [Item] {
        var seen = Set<String>()
        var out: [Item] = []
        for r in bs.weeks.flatMap(\.rows).sorted(by: { ($0.sort, $0.week) < ($1.sort, $1.week) })
        where !seen.contains(r.item_id) {
            seen.insert(r.item_id)
            out.append(Item(id: r.item_id, name: NudgeStore.shortName(r.name), perWeek: max(1, r.unit_of)))
        }
        return out
    }

    private var week: String { NudgeStore.breakfastWeek(of: iso(due)) }

    /// Most units you can ask for: what's still open that week (once), or the weekly amount.
    private func maxCount(_ it: Item) -> Int {
        weekly ? it.perWeek : bs.openRows(week: week).filter { $0.item_id == it.id }.count
    }

    /// Once: from now to the end of next week (Sunday 23:59). Weekly: any future time.
    private var dateRange: ClosedRange<Date> {
        let now = Date()
        guard !weekly, let mon = BreakfastStore.date(NudgeStore.breakfastWeek(of: iso(now))),
              let end = Calendar.current.date(byAdding: .minute, value: 14 * 24 * 60 - 1, to: mon), end > now
        else { return now...(Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now) }
        return now...end
    }

    private var plan: BreakfastPlan {
        if everything { return BreakfastPlan(mode: "all") }
        let items = catalog.compactMap { it -> BreakfastPlanItem? in
            let n = counts[it.id] ?? 0
            return n > 0 ? BreakfastPlanItem(itemId: it.id, name: it.name, count: n) : nil
        }
        return BreakfastPlan(mode: "items", items: items)
    }

    private var canSave: Bool {
        due > Date() && (everything || (plan.items ?? []).isEmpty == false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What to buy") {
                    Picker("What", selection: $everything) {
                        Text("Everything unbought").tag(true)
                        Text("Pick items").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)

                    if !everything {
                        if catalog.isEmpty {
                            Text("Open Budget once this week to load the list.")
                                .font(.subheadline).foregroundStyle(Theme.textMeta)
                        }
                        ForEach(catalog) { it in
                            let mx = maxCount(it)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.name).font(.subheadline).foregroundStyle(Theme.textMain)
                                    Text(mx == 0 ? "All bought that week" : (weekly ? "\(it.perWeek) a week" : "\(mx) left that week"))
                                        .font(.caption).foregroundStyle(Theme.textMeta)
                                }
                                Spacer()
                                Text("\(counts[it.id] ?? 0)").font(.headline.monospacedDigit())
                                    .foregroundStyle((counts[it.id] ?? 0) > 0 ? Theme.accent : Theme.textMeta)
                                    .frame(minWidth: 22)
                                Stepper("", value: Binding(get: { counts[it.id] ?? 0 },
                                                           set: { counts[it.id] = $0 }),
                                        in: 0...max(0, mx))
                                    .labelsHidden()
                                    .disabled(mx == 0)
                            }
                        }
                    }
                }

                Section {
                    DatePicker("When", selection: $due, in: dateRange)
                    Picker("Repeat", selection: $weekly) {
                        Text("Once").tag(false)
                        Text("Every week").tag(true)
                    }
                } header: { Text("When") } footer: {
                    Text(weekly
                         ? "Repeats every week at this day and time, for that week's list."
                         : "Once reminders can be set for this week or next — the weeks Budget has published.")
                }

                Section("Notification") {
                    let t = NudgeStore.breakfastText(plan, week: week)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                        if let n = t.notes { Text(n).font(.caption).foregroundStyle(Theme.textMeta) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Remind me to buy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        nudge.addBreakfastReminder(plan: plan, due: due, weekly: weekly)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            // Keep counts inside what's possible when the week or repeat changes.
            .onChange(of: due) { _, _ in clamp() }
            .onChange(of: weekly) { _, _ in
                if !dateRange.contains(due) { due = min(max(due, dateRange.lowerBound), dateRange.upperBound) }
                clamp()
            }
        }
        .tint(Theme.controlTint)
        .presentationBackground(Theme.bg)
    }

    private func clamp() {
        for it in catalog { if let c = counts[it.id], c > maxCount(it) { counts[it.id] = maxCount(it) } }
    }
}
