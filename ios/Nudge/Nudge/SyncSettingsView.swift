// SyncSettingsView.swift — Nudge (iOS)
// Settings sheet: Apple Reminders two-way sync + local reminder notifications.

import SwiftUI
import UIKit

struct SyncSettingsView: View {
    @EnvironmentObject var sync: RemindersSync
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var dedupResult: String?
    @State private var showCleanUp = false
    @AppStorage("anthropic_api_key") private var aiKey = ""
    @AppStorage("ai_reschedule_model") private var aiModel = "claude-opus-4-8"
    @State private var showDupPreview = false
    @State private var dupGroups: [DuplicateGroup] = []

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
                .listRowBackground(Theme.surface)

                // MARK: Clean up
                Section {
                    Button { showCleanUp = true } label: {
                        Label("Clean up reminders", systemImage: "trash")
                            .foregroundStyle(Theme.textMain)
                    }
                } footer: {
                    Text("Quickly delete reminders you don't need — swipe a row, or tap Select to remove several at once.")
                }
                .listRowBackground(Theme.surface)

                // MARK: AI Smart Reschedule
                Section {
                    SecureField("sk-ant-…", text: $aiKey)
                        .textInputAutocapitalization(.never).disableAutocorrection(true)
                    Picker("Model", selection: $aiModel) {
                        Text("Opus (smartest)").tag("claude-opus-4-8")
                        Text("Sonnet (balanced)").tag("claude-sonnet-4-6")
                        Text("Haiku (fast, cheap)").tag("claude-haiku-4-5")
                    }
                } header: {
                    Text("AI Smart Reschedule")
                } footer: {
                    Text("Add your Anthropic API key (console.anthropic.com) and Smart Reschedule will use Claude to spread your overdue reminders intelligently around your calendar. Stored only on this device; used only to call Anthropic. Without a key it uses the built-in planner.")
                }
                .listRowBackground(Theme.surface)

                // MARK: Upcoming
                Section {
                    NavigationLink {
                        UpcomingSectionsView().environmentObject(settings).environmentObject(store)
                    } label: {
                        Label("Sections on Upcoming", systemImage: "rectangle.3.group")
                    }
                } header: {
                    Text("Upcoming")
                } footer: {
                    Text("Pin lists (like Subscriptions or Money) to show as their own sections on the Upcoming tab, in your chosen order.")
                }
                .listRowBackground(Theme.surface)

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
                .listRowBackground(Theme.surface)

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
                    .listRowBackground(Theme.surface)
                }

                // MARK: Maintenance
                Section {
                    Button {
                        dupGroups = sync.planDuplicates()
                        if dupGroups.isEmpty { dedupResult = "No duplicates found." }
                        else { showDupPreview = true }
                    } label: {
                        Label("Remove duplicates", systemImage: "rectangle.stack.badge.minus")
                    }
                } header: {
                    Text("Maintenance")
                } footer: {
                    Text("Finds identical reminders (same title and time) and shows you exactly what it will remove — nothing is deleted until you confirm. Keeps one copy of each (an unfinished one where possible).")
                }
                .listRowBackground(Theme.surface)

                // MARK: Notifications
                Section {
                    Toggle("Reminder notifications", isOn: Binding(
                        get: { notifier.enabled },
                        set: { on in Task {
                            if on {
                                // If permission was already denied, the in-app prompt won't
                                // re-appear — send the user to the OS settings to allow it.
                                if notifier.authStatus == .denied { openOSNotificationSettings() }
                                else { await notifier.enable() }
                            } else { notifier.disable() }
                        } }
                    ))
                    if notifier.enabled {
                        HStack {
                            Text("Scheduled")
                            Spacer()
                            Text("\(notifier.scheduledCount) upcoming").foregroundStyle(Theme.textMeta)
                        }
                    }
                    // When notifications aren't authorised the in-app toggle can't grant them
                    // (iOS/macOS only prompt once) — guide the user to the right settings pane.
                    if notifier.authStatus == .denied {
                        Label(osDeniedHint, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Theme.coral)
                        Button { openOSNotificationSettings() } label: {
                            Label("Open \(osSettingsName) ▸ Notifications", systemImage: "arrow.up.forward.app")
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified when a reminder is due — earlier if it has an “early reminder” set. Only upcoming, incomplete reminders are scheduled.")
                }
                .listRowBackground(Theme.surface)

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
                .listRowBackground(Theme.surface)

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
                    Text("Your reminders are snapshotted on-device before every sync and cloud refresh (last 60 kept), so a bad merge can always be rolled back.")
                }
                .listRowBackground(Theme.surface)

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
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)            // drop the grey system Form background
            .background(Theme.bg.ignoresSafeArea())       // …and use the app's theme — themed cards
                                                          // are set per-Section via .listRowBackground
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCleanUp) { CleanUpView().environmentObject(store) }
            .sheet(isPresented: $showDupPreview) {
                DedupPreviewView(groups: dupGroups) { n in
                    dedupResult = n == 0 ? "No duplicates removed." : "Removed \(n) duplicate\(n == 1 ? "" : "s")."
                }
                .environmentObject(sync)
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

    // Notification permission must be granted in the OS settings once it's been denied.
    // These differ between Mac (System Settings) and iPhone (Settings app).
    private var osSettingsName: String {
        #if targetEnvironment(macCatalyst)
        return "System Settings"
        #else
        return "Settings"
        #endif
    }
    private var osDeniedHint: String {
        "Notifications are turned off for Nudge in \(osSettingsName) → Notifications."
    }
    private func openOSNotificationSettings() {
        #if targetEnvironment(macCatalyst)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        #else
        let url = URL(string: UIApplication.openSettingsURLString)
        #endif
        if let url { UIApplication.shared.open(url) }
    }
}
