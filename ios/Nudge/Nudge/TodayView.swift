// TodayView.swift — Nudge (iOS)
// Focused list of what's due today (plus overdue), reached by tapping the hero.

import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: NudgeStore
    @State private var editingReminder: Reminder?

    private var sections: [NudgeStore.ReminderSection] {
        store.sections().filter { $0.id == "overdue" || $0.id == "today" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if sections.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48)).foregroundStyle(Theme.sage)
                        Text("Nothing due today").font(.title3.weight(.bold)).foregroundStyle(Theme.textMain)
                        Text("You're on top of it.").font(.subheadline).foregroundStyle(Theme.textMeta)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 90)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title.uppercased())
                                .font(.caption.weight(.bold)).tracking(0.8)
                                .foregroundStyle(section.id == "overdue" ? Theme.coral : Theme.textMeta)
                                .padding(.leading, 4)
                            ForEach(section.items) { r in
                                ReminderCardView(reminder: r) { editingReminder = r }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .animation(Theme.spring, value: store.reminders)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingReminder) { r in
            AddReminderView(editing: r).environmentObject(store)
        }
    }
}
