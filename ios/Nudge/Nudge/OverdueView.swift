// OverdueView.swift — Nudge (iOS)
// The Overdue page: reminders due on a PREVIOUS calendar day. A reminder due earlier
// today stays on the Today page until midnight, then rolls in here. Self-contained —
// its own edit + smart-reschedule sheets — so it works as a presented page.

import SwiftUI

struct OverdueView: View {
    @EnvironmentObject var store: NudgeStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var editingReminder: Reminder?
    @State private var rescheduleResult: RescheduleResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                let items = store.pastDayOverdue()
                if items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Theme.sage)
                        Text("Nothing overdue").font(.title3.weight(.bold)).foregroundStyle(Theme.textMain)
                        Text("Reminders from before today show up here. Anything due today stays on the Today page until midnight.")
                            .font(.subheadline).foregroundStyle(Theme.textMeta).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 80).padding(.horizontal, 28)
                } else {
                    VStack(spacing: 12) {
                        Button {
                            let plan = store.planSmartReschedule()
                            if !plan.isEmpty { rescheduleResult = RescheduleResult(changes: plan, auto: false) }
                        } label: {
                            Label("Smart Reschedule these", systemImage: "sparkles")
                                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(settings.accentGrad, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                            ReminderCardView(reminder: r) { editingReminder = r }.popIn(i)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 30)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Overdue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingReminder) { r in AddReminderView(editing: r).environmentObject(store) }
            .sheet(item: $rescheduleResult) { SmartReschedulePreviewView(proposed: $0.changes).environmentObject(store) }
        }
        .tint(Theme.accent)
    }
}
