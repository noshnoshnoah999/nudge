// GroupViews.swift — Nudge (iOS)
// UI for the overnight AI grouping: the morning review sheet (what got grouped, with members)
// and the Settings history page (last ~month of runs). Mirrors CarryOverViews.

import SwiftUI

private func prettyDayG(_ key: String) -> String {
    let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
    guard let d = inF.date(from: key) else { return key }
    let out = DateFormatter(); out.dateFormat = "EEEE d MMMM"; return out.string(from: d)
}

/// Review one night's grouping run: each group and the reminders it collected.
struct GroupReviewView: View {
    let entry: GroupRunEntry
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("At the end of \(prettyDayG(entry.id)), Claude tidied your list by grouping \(entry.groupedCount) related reminders into \(entry.groups.count) group\(entry.groups.count == 1 ? "" : "s"). Nothing was deleted or rescheduled — tap Ungroup on any group to break it apart.")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)

                    ForEach(entry.groups) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                                Text("\(g.title) (\(g.reminderIds.count))")
                                    .font(.headline.weight(.bold)).foregroundStyle(Theme.textMain)
                                Spacer()
                                if store.reminders.contains(where: { $0.groupId == g.id }) {
                                    Button {
                                        withAnimation(Theme.spring) { store.ungroup(g.id) }
                                    } label: {
                                        Text("Ungroup").font(.caption.weight(.bold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            ForEach(Array(g.reminderTitles.enumerated()), id: \.offset) { _, t in
                                HStack(spacing: 8) {
                                    Circle().fill(Theme.textMeta.opacity(0.4)).frame(width: 5, height: 5)
                                    Text(t).font(.subheadline).foregroundStyle(Theme.textMain)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("AI Grouping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.accent)
    }
}

/// Settings → history of the last ~month of grouping runs.
struct GroupHistoryView: View {
    @ObservedObject private var log = GroupLog.shared
    @EnvironmentObject var store: NudgeStore
    @State private var selected: GroupRunEntry?

    var body: some View {
        Group {
            if log.entries.isEmpty {
                ContentUnavailableView("No grouping yet",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Each night at 23:50, Claude groups related reminders to clear clutter. You can also run it any time from the button above. Runs will appear here."))
            } else {
                List(log.entries) { e in
                    Button { selected = e } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(prettyDayG(e.id)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                                Text("\(e.groups.count) group\(e.groups.count == 1 ? "" : "s") · \(e.groupedCount) reminders")
                                    .font(.caption).foregroundStyle(Theme.textMeta)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textMeta)
                        }
                    }
                    .listRowBackground(Theme.surfaceAlt)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Grouping History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { e in GroupReviewView(entry: e).environmentObject(store) }
    }
}
