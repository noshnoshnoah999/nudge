// CarryOverViews.swift — Nudge (iOS)
// UI for the end-of-day AI carry-over: the review sheet (what was moved / kept, with reasons)
// and the Settings history page (last ~month of runs).

import SwiftUI

private func prettyDay(_ key: String) -> String {
    let inF = DateFormatter(); inF.locale = Locale(identifier: "en_US_POSIX"); inF.dateFormat = "yyyy-MM-dd"
    guard let d = inF.date(from: key) else { return key }
    let out = DateFormatter(); out.dateFormat = "EEEE d MMMM"; return out.string(from: d)
}

private func timeOnly(_ iso: String?) -> String {
    guard let d = parseDate(iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
}

/// Review one night's run: the reminders the AI moved to today, and the ones it left behind.
struct CarryOverReviewView: View {
    let entry: CarryOverEntry
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("At the end of \(prettyDay(entry.id)), Claude reviewed the reminders you hadn't finished and carried over only the ones that mattered. Your nightly & repeating routines are never touched.")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)

                    section(title: "Moved to today", icon: "arrow.right.circle.fill",
                            tint: Theme.accent, items: entry.moved, moved: true)
                    section(title: "Left in place", icon: "pause.circle.fill",
                            tint: Theme.textMeta, items: entry.kept, moved: false)
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("AI Carry-Over")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func section(title: String, icon: String, tint: Color, items: [CarryItem], moved: Bool) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text("\(title) (\(items.count))").font(.headline.weight(.bold)).foregroundStyle(Theme.textMain)
                }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                        Text(item.reason).font(.caption).foregroundStyle(Theme.textMeta)
                        if moved {
                            Text("\(timeOnly(item.oldDue)) → today \(timeOnly(item.newDue))")
                                .font(.caption2.weight(.semibold)).foregroundStyle(tint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

/// Settings → history of the last ~month of carry-over runs.
struct CarryOverHistoryView: View {
    @ObservedObject private var log = CarryOverLog.shared
    @EnvironmentObject var store: NudgeStore
    @State private var selected: CarryOverEntry?

    var body: some View {
        Group {
            if log.entries.isEmpty {
                ContentUnavailableView("No carry-overs yet",
                    systemImage: "sparkles",
                    description: Text("Each night at 23:50, Claude reviews your unfinished reminders and carries over the important ones. Runs will appear here."))
            } else {
                List(log.entries) { e in
                    Button { selected = e } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(prettyDay(e.id)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                                Text("Moved \(e.moved.count) · left \(e.kept.count)")
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
        .navigationTitle("Carry-Over History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { e in CarryOverReviewView(entry: e).environmentObject(store) }
    }
}
