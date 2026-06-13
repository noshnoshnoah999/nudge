// SmartReschedulePreviewView.swift — Nudge (iOS)
// Confirm-first Smart Reschedule: shows the proposed new date/time for each overdue
// reminder. Nothing moves until the user taps Apply; they can leave individual ones
// where they are by tapping to un-pick.

import SwiftUI

struct SmartReschedulePreviewView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let proposed: [RescheduleChange]
    @State private var excluded: Set<String> = []

    private var selected: [RescheduleChange] { proposed.filter { !excluded.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(proposed) { c in
                        Button { toggle(c.id) } label: { row(c) }.buttonStyle(.plain)
                    }
                } header: {
                    Text("\(selected.count) of \(proposed.count) will move")
                } footer: {
                    Text("Each keeps its own time of day where it had one. Tap any to leave it where it is — nothing changes until you tap Apply.")
                }
            }
            .navigationTitle("Reschedule overdue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { store.applyReschedule(selected); dismiss() }
                        .fontWeight(.bold).disabled(selected.isEmpty)
                }
            }
        }
        .presentationBackground(Theme.bg)
    }

    private func toggle(_ id: String) {
        if excluded.contains(id) { excluded.remove(id) } else { excluded.insert(id) }
    }

    private func row(_ c: RescheduleChange) -> some View {
        let on = !excluded.contains(c.id)
        return HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? Theme.accent : Theme.textMeta)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain).lineLimit(1)
                HStack(spacing: 6) {
                    if let o = parseDate(c.oldDue) {
                        Text(Self.fmt(o)).strikethrough().foregroundStyle(Theme.textMeta)
                    }
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.textMeta)
                    Text(Self.fmt(c.newDate)).foregroundStyle(Theme.accent)
                }.font(.caption)
            }
            Spacer(minLength: 0)
        }
        .opacity(on ? 1 : 0.45)
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM · HH:mm"; return f.string(from: d)
    }
}
