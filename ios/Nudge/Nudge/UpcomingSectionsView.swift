// UpcomingSectionsView.swift — Nudge (iOS)
// Pick which lists appear as their own sections on the Upcoming tab, and in what
// order. Stored in AppSettings.upcomingSections; rendered by ContentView.upcomingTab.

import SwiftUI

struct UpcomingSectionsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: NudgeStore

    var body: some View {
        List {
            Section {
                if settings.upcomingSections.isEmpty {
                    Text("No pinned lists yet. Add one below to show it as its own section at the top of the Upcoming tab.")
                        .font(.callout).foregroundStyle(Theme.textMeta)
                } else {
                    ForEach(settings.upcomingSections, id: \.self) { id in
                        if let l = store.lists.first(where: { $0.id == id }) {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: l.color)).frame(width: 10, height: 10)
                                Text(l.name).foregroundStyle(Theme.textMain)
                                Spacer()
                                Image(systemName: "line.3.horizontal").foregroundStyle(Theme.textMeta)
                            }
                        }
                    }
                    .onMove { settings.upcomingSections.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { settings.upcomingSections.remove(atOffsets: $0) }
                }
            } header: {
                Text("Sections on Upcoming")
            } footer: {
                Text("These lists show as their own sections at the top of the Upcoming tab, in this order. Drag to reorder, swipe to remove.")
            }

            let available = store.lists.filter { l in !settings.upcomingSections.contains(l.id) }
            if !available.isEmpty {
                Section("Add a list") {
                    ForEach(available) { l in
                        Button {
                            withAnimation { settings.upcomingSections.append(l.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Circle().fill(Color(hex: l.color)).frame(width: 10, height: 10)
                                Text(l.name).foregroundStyle(Theme.textMain)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Upcoming Sections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
