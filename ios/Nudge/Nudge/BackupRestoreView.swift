// BackupRestoreView.swift — Nudge (iOS)
// Lists the on-device rotating backups (newest first) and lets the user roll back to
// one. Restoring snapshots the current state first, so it's itself undoable.

import SwiftUI

struct BackupRestoreView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [NudgeStore.BackupInfo] = []
    @State private var confirm: NudgeStore.BackupInfo?
    @State private var done = false

    var body: some View {
        List {
            Section {
                if backups.isEmpty {
                    Text("No backups yet.").foregroundStyle(Theme.textMeta)
                } else {
                    ForEach(backups) { b in
                        Button { confirm = b } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.date, format: .dateTime.weekday().hour().minute().day().month())
                                        .foregroundStyle(Theme.textMain)
                                    Text("\(b.count) reminder\(b.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(Theme.textMeta)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            } footer: {
                Text("Restoring replaces your current reminders with the chosen snapshot. Your current state is backed up first, so you can undo a restore by restoring the newest snapshot.")
            }
        }
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { backups = store.listBackups() }
        .confirmationDialog("Restore this backup?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let b = confirm { store.restoreBackup(b); done = true }
                confirm = nil
            }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: {
            if let b = confirm {
                Text("Replaces current data with the snapshot from \(b.date.formatted(date: .abbreviated, time: .shortened)) (\(b.count) reminders).")
            }
        }
        .alert("Restored", isPresented: $done) {
            Button("OK") { dismiss() }
        } message: { Text("Your reminders were rolled back to the selected backup.") }
    }
}
