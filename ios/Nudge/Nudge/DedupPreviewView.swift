// DedupPreviewView.swift — Nudge (iOS)
// Confirm-first duplicate cleanup: shows each set of identical reminders (which copy is
// kept, how many are removed) so nothing is deleted until the user taps Remove. Replaces
// the old one-tap "Remove duplicates" that could silently drop the wrong copy.

import SwiftUI

struct DedupPreviewView: View {
    @EnvironmentObject var sync: RemindersSync
    @Environment(\.dismiss) private var dismiss
    let groups: [DuplicateGroup]
    var onApplied: (Int) -> Void = { _ in }

    private var removeCount: Int { groups.reduce(0) { $0 + $1.remove.count } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(displayTitle(g.keep))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                                .lineLimit(2)
                            Label("Keep this · remove \(g.remove.count) duplicate\(g.remove.count == 1 ? "" : "s")",
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Theme.accent)
                            // Show which copies go, so it's transparent.
                            ForEach(g.remove) { r in
                                Text("✕ \(copyLabel(r))").font(.caption2).foregroundStyle(Theme.textMeta)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("\(groups.count) set\(groups.count == 1 ? "" : "s") of duplicates · \(removeCount) to remove")
                } footer: {
                    Text("Each set keeps one copy — an unfinished one where possible. Removed copies are also cleared from Apple Reminders on the next sync. Nothing is deleted until you tap Remove.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Review duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Remove \(removeCount)") {
                        let n = sync.applyDuplicates(groups); onApplied(n); dismiss()
                    }
                    .fontWeight(.bold).disabled(removeCount == 0)
                }
            }
        }
        .tint(Theme.accent)
    }

    /// e.g. "completed · from Apple" / "open · added in Nudge" so the user can tell the copies apart.
    private func copyLabel(_ r: Reminder) -> String {
        let state = (r.completed ?? false) ? "completed" : "open"
        let src = r.source == "apple" ? "from Apple" : "added in Nudge"
        return "\(state) · \(src)"
    }
}
