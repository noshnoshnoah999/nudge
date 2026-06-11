// SyncSettingsView.swift — Nudge (iOS)
// Settings sheet: Apple Reminders two-way sync + local reminder notifications.

import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject var sync: RemindersSync
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDedup = false
    @State private var dedupResult: String?
    @State private var deduping = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Appearance
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Theme").font(.subheadline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(Palettes.all) { p in
                                    Button { withAnimation(Theme.spring) { settings.theme = p.id } } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle().fill(Color(hex: p.bg)).frame(width: 40, height: 40)
                                                Circle().fill(Color(hex: p.accent)).frame(width: 18, height: 18)
                                            }
                                            .overlay(Circle().stroke(settings.theme == p.id ? Color(hex: p.accent) : Color.black.opacity(0.1),
                                                                     lineWidth: settings.theme == p.id ? 2.5 : 1)
                                                .frame(width: 46, height: 46))
                                            Text(p.name).font(.caption2.weight(settings.theme == p.id ? .bold : .regular))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4).padding(.horizontal, 2)
                        }
                    }

                    Toggle("Compact list", isOn: Binding(
                        get: { settings.compact }, set: { settings.compact = $0 }))
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Pick a colour theme. Compact fits more reminders on screen.")
                }

                // MARK: Overdue
                Section {
                    NavigationLink {
                        RescheduleHistoryView().environmentObject(store)
                    } label: {
                        Label("Reschedule history", systemImage: "clock.arrow.circlepath")
                    }
                } header: {
                    Text("Overdue")
                } footer: {
                    Text("Smart Reschedule runs only when you tap it — from the Today tab or inside Triage. It spreads overdue reminders across the coming week (weekends carry more, important ones first). Every run is logged here and can be undone.")
                }

                // MARK: Privacy
                if BiometricLock.available {
                    Section {
                        Toggle("Require Face ID / Touch ID", isOn: Binding(
                            get: { settings.appLock }, set: { settings.appLock = $0 }))
                    } header: {
                        Text("Privacy")
                    } footer: {
                        Text("Lock Nudge so it asks for Face ID, Touch ID, or your passcode each time you open it.")
                    }
                }

                // MARK: Maintenance
                Section {
                    Button {
                        confirmDedup = true
                    } label: {
                        HStack {
                            Label("Remove duplicates", systemImage: "rectangle.stack.badge.minus")
                            Spacer()
                            if deduping { ProgressView() }
                        }
                    }
                    .disabled(deduping)
                } header: {
                    Text("Maintenance")
                } footer: {
                    Text("Collapse identical reminders (same title and time) to a single copy — on both Nudge and Apple Reminders. Use this to clean up duplicates from earlier sync issues.")
                }

                // MARK: Notifications
                Section {
                    Toggle("Reminder notifications", isOn: Binding(
                        get: { notifier.enabled },
                        set: { on in Task { if on { await notifier.enable() } else { notifier.disable() } } }
                    ))
                    if notifier.enabled {
                        HStack {
                            Text("Scheduled")
                            Spacer()
                            Text("\(notifier.scheduledCount) upcoming").foregroundStyle(Theme.textMeta)
                        }
                    }
                    if notifier.authStatus == .denied {
                        Label("Notifications are off in iOS Settings → Nudge", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Theme.coral)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified when a reminder is due — earlier if it has an “early reminder” set. Only upcoming, incomplete reminders are scheduled.")
                }

                // MARK: Apple Reminders sync
                Section {
                    Toggle("Sync with Apple Reminders", isOn: Binding(
                        get: { sync.enabled },
                        set: { on in Task { if on { await sync.enable() } else { sync.disable() } } }
                    ))
                    if sync.enabled {
                        Button {
                            Task { await sync.syncNow() }
                        } label: {
                            Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isSyncing)

                        HStack {
                            Text("Status")
                            Spacer()
                            syncStatusView.foregroundStyle(Theme.textMeta)
                        }
                        if let t = sync.lastSync {
                            HStack {
                                Text("Last synced")
                                Spacer()
                                Text(t, format: .relative(presentation: .named)).foregroundStyle(Theme.textMeta)
                            }
                        }
                    }
                } header: {
                    Text("Apple Reminders")
                } footer: {
                    Text("Mirrors a dedicated **Nudge** list in Apple Reminders. Your other lists are never touched. Anything you capture in either place — Siri, Control Center, Apple Watch, or here — stays in sync.")
                }

                // MARK: Backups
                Section {
                    HStack {
                        Label("Last backup", systemImage: "checkmark.shield")
                        Spacer()
                        if let b = store.lastBackup {
                            Text(b.date, format: .relative(presentation: .named)).foregroundStyle(Theme.textMeta)
                        } else {
                            Text("none yet").foregroundStyle(Theme.textMeta)
                        }
                    }
                    if let b = store.lastBackup {
                        HStack {
                            Text("Snapshots kept")
                            Spacer()
                            Text("\(b.count)").foregroundStyle(Theme.textMeta)
                        }
                        NavigationLink {
                            BackupRestoreView().environmentObject(store)
                        } label: {
                            Label("Restore from backup…", systemImage: "clock.arrow.circlepath")
                        }
                    }
                } header: {
                    Text("Safety")
                } footer: {
                    Text("Your reminders are snapshotted on-device before every sync and cloud refresh (last 40 kept), so a bad merge can always be rolled back.")
                }

                // MARK: About
                Section("About") {
                    NavigationLink {
                        DesignGalleryView()
                    } label: {
                        Label("Preview designs (beta)", systemImage: "paintpalette")
                    }
                    NavigationLink {
                        ChangelogView()
                    } label: {
                        Label("What's New", systemImage: "sparkles")
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("v\(Changelog.entries.first?.version ?? "1.0")").foregroundStyle(Theme.textMeta)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Remove duplicate reminders?", isPresented: $confirmDedup, titleVisibility: .visible) {
                Button("Remove duplicates", role: .destructive) {
                    deduping = true
                    Task {
                        let n = await sync.deduplicate()
                        deduping = false
                        dedupResult = n == 0 ? "No duplicates found." : "Removed \(n) duplicate\(n == 1 ? "" : "s")."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Keeps one copy of each identical reminder, on both Nudge and Apple Reminders. This can't be undone.")
            }
            .alert("Cleanup", isPresented: Binding(get: { dedupResult != nil }, set: { if !$0 { dedupResult = nil } })) {
                Button("OK") { dedupResult = nil }
            } message: { Text(dedupResult ?? "") }
        }
        .tint(Theme.violet)
        .presentationBackground(Theme.bg)
    }

    private var isSyncing: Bool {
        if case .syncing = sync.status { return true }
        return false
    }

    @ViewBuilder private var syncStatusView: some View {
        switch sync.status {
        case .idle:         Text("Ready")
        case .syncing:      HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Syncing…") }
        case .ok(let s):    Text(s)
        case .denied:       Text("Access denied — enable in Settings").foregroundStyle(Theme.coral)
        case .error(let m): Text(m).foregroundStyle(Theme.coral)
        }
    }
}
