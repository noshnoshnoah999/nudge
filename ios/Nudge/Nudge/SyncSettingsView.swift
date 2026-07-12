// SyncSettingsView.swift — Nudge (iOS)
// Settings sheet: Apple Reminders two-way sync + local reminder notifications.

import SwiftUI
import UIKit
import WidgetKit

struct SyncSettingsView: View {
    @EnvironmentObject var sync: RemindersSync
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var dedupResult: String?
    @State private var showCleanUp = false
    @AppStorage("anthropic_api_key") private var aiKey = ""
    @State private var showDupPreview = false
    @State private var dupGroups: [DuplicateGroup] = []
    @AppStorage("autoGroupNightly") private var autoGroupNightly = true
    @State private var groupingBusy = false
    @State private var groupingResult: String?
    @State private var session: Session? = AuthStore.load()
    @State private var authEmail = ""
    @State private var authCode = ""
    @State private var codeSent = false
    @State private var authBusy = false
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Appearance
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Theme").font(.subheadline)
                        // All 8 palettes wrap into a 4-column grid (2 even rows, no gaps)
                        // so none are hidden off-screen (Ocean used to be clipped past the
                        // right edge of a horizontal scroll).
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                                  spacing: 14) {
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
                                        Text(p.name)
                                            .font(.caption2.weight(settings.theme == p.id ? .bold : .regular))
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Toggle("Compact list", isOn: Binding(
                        get: { settings.compact }, set: { settings.compact = $0 }))

                    Toggle("Bold text", isOn: Binding(
                        get: { settings.boldText }, set: { settings.boldText = $0 }))

                    Toggle("Sound & haptics on complete", isOn: Binding(
                        get: { settings.celebrationFeedback }, set: { settings.celebrationFeedback = $0 }))
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Pick a colour theme. Compact fits more reminders on screen. Bold text renders the app in a heavier weight. Turn off Sound & haptics to keep the completion animation silent.")
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

                // MARK: Cloud sync (Supabase Auth)
                Section {
                    if let s = session {
                        HStack {
                            Text("Signed in").foregroundStyle(Theme.textMain)
                            Spacer()
                            Text(s.email ?? "—").foregroundStyle(Theme.textMeta)
                        }
                        Button(role: .destructive) {
                            AuthStore.clear()
                            session = nil; codeSent = false; authCode = ""; authError = nil
                            WidgetCenter.shared.reloadAllTimelines()
                        } label: {
                            Text("Sign out")
                        }
                    } else {
                        TextField("you@example.com", text: $authEmail)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                        if codeSent {
                            TextField("6-digit code", text: $authCode)
                                .keyboardType(.numberPad)
                                .disableAutocorrection(true)
                        }
                        Button {
                            Task { codeSent ? await verifyCode() : await sendCode() }
                        } label: {
                            HStack {
                                Text(codeSent ? "Verify code" : "Send code")
                                if authBusy { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(authBusy || (codeSent ? authCode.isEmpty : authEmail.isEmpty))
                        if codeSent {
                            Button("Use a different email") {
                                codeSent = false; authCode = ""; authError = nil
                            }
                            .foregroundStyle(Theme.textMeta)
                        }
                        if let e = authError {
                            Text(e).font(.footnote).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Cloud sync")
                } footer: {
                    Text(session == nil
                         ? "Sign in to sync reminders across your devices. We email you a 6-digit code — no password. Signed out, Nudge keeps working on this device and never uploads or erases anything."
                         : "Reminders sync to your private row, protected by row-level security. Signing out leaves your local data untouched.")
                }
                .listRowBackground(Theme.surface)

                // MARK: AI Smart Reschedule
                Section {
                    SecureField("sk-ant-…", text: $aiKey)
                        .textInputAutocapitalization(.never).disableAutocorrection(true)
                    HStack {
                        Text("Model").foregroundStyle(Theme.textMain)
                        Spacer()
                        Text("Sonnet").foregroundStyle(Theme.textMeta)
                    }
                } header: {
                    Text("AI features")
                } footer: {
                    Text("Add your Anthropic API key (console.anthropic.com). Smart Reschedule and the end-of-day carry-over both run on Claude Sonnet — a good balance of quality and cost (never the pricier Opus). Stored only on this device; used only to call Anthropic. Without a key, Smart Reschedule uses the built-in planner.")
                }
                .listRowBackground(Theme.surface)

                // MARK: End-of-day AI carry-over
                Section {
                    NavigationLink {
                        CarryOverHistoryView().environmentObject(store)
                    } label: {
                        Label("Carry-Over History", systemImage: "sparkles")
                            .foregroundStyle(Theme.textMain)
                    }
                } header: {
                    Text("End-of-day Carry-Over")
                } footer: {
                    Text("Each night at 23:50, Claude reviews the reminders you didn't finish and carries over only the important ones to the next day. Nightly and repeating routines are never moved. See the last month of runs here.")
                }
                .listRowBackground(Theme.surface)

                // MARK: Group reminders
                Section {
                    Button {
                        guard !groupingBusy else { return }
                        groupingBusy = true; groupingResult = nil
                        Task {
                            let n = await store.groupNowAI()
                            await MainActor.run {
                                groupingBusy = false
                                switch n {
                                case .none:      groupingResult = "Add an API key above to use AI grouping."
                                case .some(0):   groupingResult = "Nothing to group right now."
                                case .some(let c): groupingResult = "Grouped \(c) reminder\(c == 1 ? "" : "s")."
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Label("Group similar reminders now", systemImage: "folder.badge.plus")
                                .foregroundStyle(Theme.textMain)
                            Spacer()
                            if groupingBusy { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(groupingBusy)

                    if let r = groupingResult {
                        Text(r).font(.caption).foregroundStyle(Theme.textMeta)
                    }

                    Toggle("Group automatically at 23:50", isOn: $autoGroupNightly)

                    NavigationLink {
                        GroupHistoryView().environmentObject(store)
                    } label: {
                        Label("Grouping history", systemImage: "folder")
                            .foregroundStyle(Theme.textMain)
                    }
                } header: {
                    Text("Group reminders")
                } footer: {
                    Text("Claude bundles related reminders (same theme, project, or errand) into one collapsible card to clear clutter — tap a group to see everything inside. Nothing is deleted or rescheduled, and Ungroup undoes it instantly. Only reminders with no date, or due more than 3 days out, are grouped, so nothing overdue or coming up soon gets hidden. Runs on tap and, when the toggle is on, automatically each night at 23:50 (you'll see an orange banner to review it next morning).")
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

    // MARK: - Cloud sign-in
    private func sendCode() async {
        authBusy = true; authError = nil
        defer { authBusy = false }
        do {
            try await Auth.sendCode(email: authEmail.trimmingCharacters(in: .whitespaces))
            codeSent = true
        } catch {
            authError = error.localizedDescription
        }
    }

    private func verifyCode() async {
        authBusy = true; authError = nil
        defer { authBusy = false }
        do {
            try await Auth.verifyCode(email: authEmail.trimmingCharacters(in: .whitespaces),
                                      token: authCode.trimmingCharacters(in: .whitespaces))
            session = AuthStore.load()
            authCode = ""; codeSent = false
            await store.refresh()                      // pull the cloud copy now that we can read it
            WidgetCenter.shared.reloadAllTimelines()   // widget reads the new session from the Keychain
        } catch {
            authError = error.localizedDescription
        }
    }
}
