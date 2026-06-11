// CompletedHistoryView.swift — Nudge (iOS)
// A history of completed reminders, grouped by day. Tap the check to restore one.

import SwiftUI

struct CompletedHistoryView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss

    private var groups: [(day: String, items: [Reminder])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: store.completedReminders()) { r -> Date in
            cal.startOfDay(for: parseDate(r.completedAt) ?? .distantPast)
        }
        return dict.keys.sorted(by: >).map { (dayLabel($0), dict[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if groups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("Nothing completed yet").font(.headline).foregroundStyle(Theme.textMain)
                        Text("Reminders you finish will collect here.")
                            .font(.subheadline).foregroundStyle(Theme.textMeta).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 70).padding(.horizontal, 30)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.day) { g in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 7) {
                                    Text(g.day.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
                                        .foregroundStyle(Theme.accent)
                                    Text("\(g.items.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Theme.surfaceAlt, in: Capsule())
                                }
                                .padding(.leading, 2)
                                ForEach(g.items) { row($0) }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Completed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }

    private func row(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation(Theme.spring) { store.toggleComplete(r) } } label: {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle(r)).font(.subheadline).foregroundStyle(Theme.textMeta)
                    .strikethrough(true, color: Theme.textMeta.opacity(0.5))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let t = parseDate(r.completedAt) {
                        Text(t, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(Theme.textMeta)
                    }
                    if let l = store.list(for: r.listId)?.name {
                        Text("· \(l)").font(.caption).foregroundStyle(Theme.textMeta)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .transition(.opacity)
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .year) ? "EEEE d MMM" : "d MMM yyyy"
        return f.string(from: d)
    }
}
