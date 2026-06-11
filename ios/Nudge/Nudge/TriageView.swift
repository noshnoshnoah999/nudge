// TriageView.swift — Nudge (iOS)
// Targeted triage: Smart Reschedule defers the bulk; this surfaces only the
// reminders you keep avoiding (moved 3+ times) so you decide keep-or-delete on
// the handful that actually need a human call.

import SwiftUI

struct TriageView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    var onSmartReschedule: (() -> Void)? = nil

    @State private var items: [(r: Reminder, count: Int)] = []
    @State private var keptCount = 0
    @State private var deletedCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        Text("These keep getting auto-rescheduled instead of done. Keep the ones that matter — delete the rest. Everything else just keeps deferring itself.")
                            .font(.subheadline).foregroundStyle(Theme.textMeta)
                        ForEach(items, id: \.r.id) { item in card(item) }
                    }
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Worth keeping?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { items = store.stuckReminders() }
        }
        .tint(Theme.accent)
    }

    private func card(_ item: (r: Reminder, count: Int)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displayTitle(item.r)).font(.headline).foregroundStyle(Theme.textMain)
                .fixedSize(horizontal: false, vertical: true)
            Label("Rescheduled \(item.count)× · keeps lapsing", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.coral)
            HStack(spacing: 12) {
                Button { remove(item.r); store.deleteReminder(item.r); deletedCount += 1 } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMeta)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                Button { remove(item.r); store.acknowledgeKeep(item.r.id); keptCount += 1 } label: {
                    Label("Keep", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func remove(_ r: Reminder) {
        withAnimation(Theme.spring) { items.removeAll { $0.r.id == r.id } }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(Theme.accent)
            Text(keptCount + deletedCount > 0 ? "All sorted" : "Nothing stuck")
                .font(.title3.weight(.bold)).foregroundStyle(Theme.textMain)
            Text(keptCount + deletedCount > 0
                 ? "Kept \(keptCount), deleted \(deletedCount). Anything overdue keeps auto-rescheduling for you."
                 : "Nothing's been avoided enough to need a decision. Overdue items just get spread across the week automatically.")
                .font(.subheadline).foregroundStyle(Theme.textMeta)
                .multilineTextAlignment(.center)
            if let onSmart = onSmartReschedule, store.overdueCount() > 0 {
                Button { onSmart() } label: {
                    Label("Reschedule overdue now", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle()).padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
    }
}
