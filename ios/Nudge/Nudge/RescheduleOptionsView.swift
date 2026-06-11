// RescheduleOptionsView.swift — Nudge
// Opened from a notification's "Reschedule…" action. Offers a smart suggestion
// (with the exact new day/time shown) or a manual pick.

import SwiftUI

struct RescheduleOptionsView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let reminder: Reminder
    @State private var manualDate: Date

    init(reminder: Reminder) {
        self.reminder = reminder
        _manualDate = State(initialValue: parseDate(reminder.dueDate) ?? Date().addingTimeInterval(3600))
    }

    private var smart: Date { SmartScheduler.suggestSlot(for: reminder) }
    private func long(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM · HH:mm"; return f.string(from: d)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayTitle(reminder)).font(.title3.weight(.bold)).foregroundStyle(Theme.textMain)
                        if let lbl = dueLabel(reminder) {
                            Text("Currently \(lbl)").font(.subheadline).foregroundStyle(Theme.textMeta)
                        }
                    }

                    // Smart suggestion
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SMART").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent)
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Move to").font(.caption).foregroundStyle(Theme.textMeta)
                                Text(long(smart)).font(.headline).foregroundStyle(Theme.textMain)
                            }
                        }
                        Button {
                            store.reschedule(reminder.id, to: smart); dismiss()
                        } label: {
                            Text("Use this time").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    // Manual pick
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OR PICK A TIME").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                        DatePicker("", selection: $manualDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical).tint(Theme.accent).labelsHidden()
                        Button {
                            store.reschedule(reminder.id, to: manualDate); dismiss()
                        } label: {
                            Text("Reschedule to this").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity).padding(12)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }
}
