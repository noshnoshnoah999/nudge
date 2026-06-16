// CleanUpView.swift — Nudge (iOS)
// Quick bulk delete for clearing out reminders you don't need. A real List (not the
// custom card ScrollView) so it gets native swipe-to-delete AND multi-select "Edit"
// mode for free — neither fights the scroll the way a per-card gesture did.

import SwiftUI

struct CleanUpView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var includeCompleted = false
    @State private var selection = Set<String>()
    @State private var editMode: EditMode = .inactive

    /// Open (or, optionally, completed) reminders, oldest due first so clutter surfaces.
    private var rows: [Reminder] {
        store.reminders
            .filter { !($0.dismissed ?? false) }
            .filter { includeCompleted || !($0.completed ?? false) }
            .sorted { (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    Toggle("Include completed", isOn: $includeCompleted.animation())
                        .tint(Theme.accent)
                }
                Section {
                    ForEach(rows) { r in row(r).tag(r.id) }
                        .onDelete { idx in delete(idx.map { rows[$0] }) }   // swipe-to-delete
                } header: {
                    Text(rows.isEmpty ? "Nothing to clean up"
                         : "\(rows.count) reminders · swipe to delete, or tap Select for several")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .environment(\.editMode, $editMode)
            .navigationTitle("Clean up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editMode.isEditing ? "Cancel" : "Select") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active; selection.removeAll() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if editMode.isEditing && !selection.isEmpty {
                        Button(role: .destructive) { deleteSelected() } label: {
                            Label("Delete \(selection.count)", systemImage: "trash")
                                .font(.headline).foregroundStyle(Theme.coral)
                        }
                    }
                }
            }
        }
        .tint(Theme.accent)
    }

    private func row(_ r: Reminder) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayTitle(r)).foregroundStyle(Theme.textMain).lineLimit(1)
                .strikethrough(r.isCompleted, color: Theme.textMeta)
            HStack(spacing: 6) {
                if let d = parseDate(r.dueDate) {
                    Text(Self.fmt(d)).foregroundStyle(store.isOverdue(r) ? Theme.coral : Theme.textMeta)
                }
                if let l = store.list(for: r.listId) {
                    Text("· \(l.name)").foregroundStyle(Theme.textMeta)
                }
            }.font(.caption)
        }
    }

    private func delete(_ targets: [Reminder]) {
        withAnimation { for r in targets { store.deleteReminder(r) } }
    }
    private func deleteSelected() {
        let targets = rows.filter { selection.contains($0.id) }
        delete(targets)
        selection.removeAll()
        if rows.isEmpty { withAnimation { editMode = .inactive } }
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d)
    }
}
