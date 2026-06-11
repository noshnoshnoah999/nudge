// RescheduleSummaryView.swift — Nudge (iOS)
// Shows what Smart Reschedule moved (grouped by day) with an Undo.

import SwiftUI

struct RescheduleSummaryView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let result: RescheduleResult
    @State private var undone = false
    @State private var shown = false

    private var grouped: [(day: String, items: [RescheduleChange])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: result.changes) { cal.startOfDay(for: $0.newDate) }
        return dict.keys.sorted().map { key in
            let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
            return (f.string(from: key), dict[key]!.sorted { $0.newDate < $1.newDate })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: undone ? "arrow.uturn.backward.circle.fill" : "sparkles")
                            .font(.largeTitle).foregroundStyle(Theme.accent)
                        Text(undone ? "Reverted" : "Spread \(result.changes.count) reminders")
                            .font(.title2.weight(.bold)).foregroundStyle(Theme.textMain)
                        Text(undone ? "Everything's back where it was."
                             : "\(result.auto ? "Auto-rescheduled" : "Rescheduled") across \(grouped.count) day\(grouped.count == 1 ? "" : "s") so the pile doesn't pile up.")
                            .font(.subheadline).foregroundStyle(Theme.textMeta)
                    }

                    if !undone {
                        ForEach(Array(grouped.enumerated()), id: \.element.day) { gi, g in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(g.day.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
                                    .foregroundStyle(Theme.accent)
                                ForEach(Array(g.items.enumerated()), id: \.element.id) { ii, c in
                                    HStack(spacing: 10) {
                                        Text(c.title).font(.subheadline).foregroundStyle(Theme.textMain).lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(c.newDate, format: .dateTime.hour().minute())
                                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.textMeta)
                                    }
                                    .padding(12)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .opacity(shown ? 1 : 0)
                                    .offset(x: shown ? 0 : 60)
                                    .animation(Theme.spring.delay(Double(gi) * 0.12 + Double(ii) * 0.05), value: shown)
                                }
                            }
                            .opacity(shown ? 1 : 0)
                            .animation(Theme.spring.delay(Double(gi) * 0.12), value: shown)
                        }
                    }
                }
                .padding(18)
                .onAppear { shown = true }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Smart Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !undone {
                        Button("Undo") { store.undoReschedule(result.changes); undone = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.accent)
    }
}
