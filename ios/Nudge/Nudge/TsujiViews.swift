// TsujiViews.swift — Nudge (iOS + Mac Catalyst)
// Tsuji Action Banner, step 2 — the UI.
//
//  • TsujiBanner        — on Home (under the birthday banners) and at the top of Today
//                         (Noah, 1 Nov 2026). Shown only when something is Missing, Overdue or
//                         due within 7 days. "Now" + "Next steps", collapsible.
//  • TsujiItemSheet     — Nudge's own read-only details sheet (Noah, 1 Nov 2026).
//  • TsujiClearSheet    — the ONLY way to clear: type the phrase, which is shown on screen.
//  • TsujiPlanListView  — Settings → Tsuji plan → Plan: all 13 with their status.
//  • TsujiTestToolsView — Settings → Tsuji plan → Test tools (only while Test mode is on).
//
// Each is its own View struct, kept out of ContentView.body (see MoveOverBanner.swift for the
// iPhone main-thread stack overflow that taught us this).
//
// There is deliberately NO swipe action, long-press, tick box or notification action that
// clears an item.

import SwiftUI

// MARK: - Formatting

enum TsujiFormat {
    static func date(_ d: Date?) -> String {
        guard let d else { return "no date" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return f.string(from: d)
    }

    static func dateRange(_ item: TsujiStore.Item) -> String {
        if let end = item.end { return "\(date(item.start)) – \(date(end))" }
        return date(item.start)
    }

    static func relative(_ s: TsujiStore.Status) -> String {
        switch s {
        case .missing: return "missing from calendar"
        case .duplicate(let n): return "appears \(n) times in Tsuji Plan"
        case .overdue(let n): return n == 1 ? "1 day overdue" : "\(n) days overdue"
        case .dueSoon(let n): return n == 0 ? "today" : (n == 1 ? "tomorrow" : "in \(n) days")
        case .later(let n): return "in \(n) days"
        case .cleared: return "cleared"
        }
    }

    static func line(_ item: TsujiStore.Item) -> String {
        switch item.status {
        case .missing:
            if let s = item.start { return "Missing from calendar — was due \(date(s))" }
            return "Missing from calendar"
        case .duplicate(let n):
            return "Appears \(n) times in Tsuji Plan — fix it in Calendar"
        default:
            return "\(dateRange(item)) · \(relative(item.status))"
        }
    }

    static func color(_ s: TsujiStore.Status) -> Color {
        switch s {
        case .missing, .duplicate, .overdue: return Theme.coral
        case .dueSoon: return Theme.accent
        case .later, .cleared: return Theme.textMeta
        }
    }
}

// MARK: - Banner

struct TsujiBanner: View {
    @ObservedObject private var tsuji = TsujiStore.shared
    @State private var sheet: SheetKind?

    enum SheetKind: Identifiable {
        case detail(TsujiStore.Item)
        case clear(TsujiStore.Item)
        var id: String {
            switch self {
            case .detail(let i): return "detail-\(i.id)"
            case .clear(let i): return "clear-\(i.id)"
            }
        }
    }

    var body: some View {
        // `|| sheet != nil`: clearing the last "Now" item hides the banner, and a sheet attached
        // to a view that disappears is dismissed with it — Noah would never see the result.
        // Keep the card while one of its sheets is open.
        if tsuji.bannerVisible || sheet != nil {
            card
        }
    }

    private var card: some View {
        let now = tsuji.nowItems
        let next = tsuji.nextItems
        return VStack(alignment: .leading, spacing: 10) {
            header(nowCount: now.count)
            if !tsuji.collapsed {
                if let p = tsuji.problem {
                    Text(p).font(.caption).foregroundStyle(Theme.coral)
                }
                if !now.isEmpty {
                    sectionLabel("NOW")
                    ForEach(now) { item in row(item, showClear: true) }
                }
                if !next.isEmpty {
                    sectionLabel("NEXT STEPS")
                    ForEach(next) { item in row(item, showClear: false) }
                }
            }
        }
        .padding(12)
        .background {
            if Theme.minimal {
                Rectangle().fill(Theme.surface)
            } else {
                RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous).fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1))
            }
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .detail(let item): TsujiItemSheet(item: item)
            case .clear(let item): TsujiClearSheet(item: item)
            }
        }
    }

    private func header(nowCount: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tsuji plan").font(.subheadline.weight(.bold)).foregroundStyle(Theme.textMain)
                Text(summary(nowCount: nowCount)).font(.caption).foregroundStyle(Theme.textMeta)
            }
            if tsuji.testMode {
                Text("TEST MODE")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.coral.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.coral)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(Theme.spring) { tsuji.setCollapsed(!tsuji.collapsed) }
            } label: {
                Image(systemName: tsuji.collapsed ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textMeta)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tsuji.collapsed ? "Expand Tsuji plan" : "Collapse Tsuji plan")
        }
    }

    private func summary(nowCount: Int) -> String {
        if tsuji.problem != nil { return "Needs attention" }
        let base = nowCount == 1 ? "1 item needs doing" : "\(nowCount) items need doing"
        return tsuji.testMode ? "\(base) · pretend today: \(TsujiFormat.date(tsuji.effectiveToday))" : base
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.textMeta)
            .padding(.top, 2)
    }

    private func row(_ item: TsujiStore.Item, showClear: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                sheet = .detail(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textMain)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(TsujiFormat.line(item))
                        .font(.caption)
                        .foregroundStyle(TsujiFormat.color(item.status))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showClear && item.canClear {
                Button("Clear") { sheet = .clear(item) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Details sheet (read-only)

struct TsujiItemSheet: View {
    let item: TsujiStore.Item
    @Environment(\.dismiss) private var dismiss
    @State private var clearing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.title).font(.headline)
                    LabeledContent("Date", value: TsujiFormat.dateRange(item))
                    LabeledContent("Status", value: statusText)
                }
                .listRowBackground(Theme.surface)

                if !item.notes.isEmpty {
                    Section("Notes from Calendar") {
                        Text(item.notes)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                    .listRowBackground(Theme.surface)
                }

                if !stateNotes.isEmpty {
                    Section {
                        ForEach(stateNotes, id: \.self) { Text($0).font(.footnote) }
                    }
                    .listRowBackground(Theme.surface)
                }

                if item.canClear {
                    Section {
                        Button("Clear this item…") { clearing = true }
                    } footer: {
                        Text("You'll type a short phrase to confirm. It's shown on the next screen.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(item.number > 0 ? "Tsuji #\(item.number)" : "Tsuji test entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $clearing) {
                TsujiClearSheet(item: item, onCleared: { dismiss() })
            }
        }
    }

    private var statusText: String {
        switch item.status {
        case .cleared: return "Cleared"
        case .missing: return "Missing from calendar"
        case .duplicate(let n): return "Appears \(n) times"
        default:
            let s = TsujiFormat.relative(item.status)   // "in 6 days" → "In 6 days"
            return s.prefix(1).uppercased() + s.dropFirst()
        }
    }

    private var stateNotes: [String] {
        var n: [String] = []
        if item.isTestEntry { n.append("Test entry — only shown while Test mode is on.") }
        if item.dryRun { n.append("Cleared inside Nudge only. Saving to Calendar is switched off in this build.") }
        if item.calendarNotUpdated { n.append("Calendar not updated yet. Nudge will try again next time it opens.") }
        if item.reopenedWithoutBackup {
            n.append("Reopened. This device didn't clear it, so it has no copy of the Calendar alerts. The device that cleared it restores them next time Nudge opens there.")
        }
        if case .missing = item.status {
            n.append("Nudge can't find this event in your Tsuji Plan calendar. Clearing it here only clears it inside Nudge.")
        }
        if case .duplicate = item.status {
            n.append("This event is in Tsuji Plan more than once, so Nudge won't guess which one is real. Delete the extra copy in Calendar.")
        }
        return n
    }
}

// MARK: - Clear sheet (typed confirmation)

struct TsujiClearSheet: View {
    let item: TsujiStore.Item
    var onCleared: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var result: TsujiStore.ClearResult?
    @FocusState private var fieldFocused: Bool

    private var matches: Bool { TsujiPlan.phraseMatches(typed) }

    private var clearedMessage: String? {
        if case .cleared(let m)? = result { return m }
        return nil
    }

    private var refusedReasons: [String] {
        if case .refused(let r)? = result { return r }
        return []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.title).font(.headline)
                    Text(TsujiFormat.line(item)).font(.subheadline).foregroundStyle(Theme.textMeta)
                }
                .listRowBackground(Theme.surface)

                if let msg = clearedMessage {
                    Section {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.textMain)
                        Button("Done") {
                            dismiss()
                            onCleared()
                        }
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    Section {
                        Text("Type this phrase to clear the item:")
                            .font(.subheadline)
                        Text(TsujiPlan.confirmPhrase)
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .foregroundStyle(Theme.textMain)
                            .textSelection(.enabled)
                        TextField(TsujiPlan.confirmPhrase, text: $typed)
                            .autocorrectionDisabled(true)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                    } footer: {
                        Text("This is just a confirmation that the task is really done. The phrase is shown above, so there's nothing to remember.")
                    }
                    .listRowBackground(Theme.surface)

                    if !refusedReasons.isEmpty {
                        Section("Nudge didn't clear it") {
                            ForEach(refusedReasons, id: \.self) { Text($0).font(.footnote) }
                        }
                        .listRowBackground(Theme.surface)
                    }

                    if !TsujiPlan.calendarWritesEnabled {
                        Section {
                            Text("Test build: saving to Calendar is switched off, so this only clears the item inside Nudge. Your calendar won't change.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textMeta)
                        }
                        .listRowBackground(Theme.surface)
                    }

                    Section {
                        Button("Clear item") {
                            result = TsujiStore.shared.clear(uid: item.id, typed: typed)
                        }
                        .disabled(!matches)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Clear item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(clearedMessage == nil ? "Cancel" : "Close") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
    }
}

// MARK: - Settings → Tsuji plan → Plan

struct TsujiPlanListView: View {
    @ObservedObject private var tsuji = TsujiStore.shared
    @State private var detail: TsujiStore.Item?

    var body: some View {
        Form {
            if let p = tsuji.problem {
                Section {
                    Text(p).font(.footnote).foregroundStyle(Theme.coral)
                }
                .listRowBackground(Theme.surface)
            }
            if tsuji.testMode {
                Section {
                    Text("Test mode is on. Nudge is pretending today is \(TsujiFormat.date(tsuji.effectiveToday)).")
                        .font(.footnote).foregroundStyle(Theme.coral)
                }
                .listRowBackground(Theme.surface)
            }
            Section {
                ForEach(tsuji.items) { item in
                    Button {
                        detail = item
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.number > 0 ? "\(item.number)" : "T")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.textMeta)
                                .frame(width: 22, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline)
                                    .foregroundStyle(item.status == .cleared ? Theme.textMeta : Theme.textMain)
                                    .multilineTextAlignment(.leading)
                                Text(TsujiFormat.line(item))
                                    .font(.caption)
                                    .foregroundStyle(TsujiFormat.color(item.status))
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Titles and dates come live from your Tsuji Plan calendar. Change a date in Calendar and Nudge follows.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Tsuji plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tsuji.reload() }
        .sheet(item: $detail) { item in TsujiItemSheet(item: item) }
    }
}

// MARK: - Settings → Tsuji plan → Test tools (Test mode only)

struct TsujiTestToolsView: View {
    @ObservedObject private var tsuji = TsujiStore.shared
    @State private var selfTest: [String] = []
    @State private var pending: [TsujiNotifications.PendingInfo] = []
    @State private var pendingLoaded = false
    @State private var sendNote: String?
    @State private var resetDone = false

    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Pretend today is", selection: $tsuji.fakeToday, displayedComponents: .date)
                Button("29 Oct 2026 (Test 1)") { tsuji.fakeToday = Self.day(2026, 10, 29) }
                Button("3 Jan 2027 (Test 2)") { tsuji.fakeToday = Self.day(2027, 1, 3) }
                Button("12 Jan 2027 (Test 3)") { tsuji.fakeToday = Self.day(2027, 1, 12) }
            } header: {
                Text("Date")
            } footer: {
                Text("Only the Tsuji banner, the plan list and Tsuji notifications use this date. Notification times move with it: an alert for the pretend date fires at 09:00 on the real date.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle("Add a made-up missing event (Test 8)", isOn: $tsuji.testMissingEntry)
                Toggle("Add the open campus event with an invitee (Test 9)", isOn: $tsuji.testInviteeEntry)
            } header: {
                Text("Test entries")
            } footer: {
                Text(TsujiPlan.calendarWritesEnabled
                     ? "Not available: saving to Calendar is switched on in this build."
                     : "Saving to Calendar is switched off in this build, so Nudge can't edit these events even if a check went wrong.")
            }
            .disabled(TsujiPlan.calendarWritesEnabled)
            .listRowBackground(Theme.surface)

            Section {
                Button("Run safety self-test") { selfTest = TsujiStore.selfTest() }
                ForEach(Array(selfTest.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(.footnote, design: .monospaced))
                }
            } header: {
                Text("Safety checks")
            } footer: {
                Text("Checks the safety rules and the typed phrase with made-up values. It doesn't touch any real event.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Show scheduled Tsuji notifications") {
                    Task {
                        pending = await TsujiNotifications.pendingInfo()
                        pendingLoaded = true
                    }
                }
                if pendingLoaded && pending.isEmpty {
                    Text("None scheduled on this device.").font(.footnote).foregroundStyle(Theme.textMeta)
                }
                ForEach(pending) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.footnote)
                        Text(p.when).font(.caption).foregroundStyle(Theme.textMeta)
                    }
                }
                Button("Send a sample notification in 5 seconds") {
                    Task { sendNote = await TsujiNotifications.sendTestNow() }
                }
                if let s = sendNote { Text(s).font(.footnote).foregroundStyle(Theme.textMeta) }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Nudge's notifications must be switched on in Settings.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Reset test clears", role: .destructive) {
                    tsuji.resetTestClears()
                    resetDone = true
                }
                if resetDone { Text("Done. Test clears were undone.").font(.footnote).foregroundStyle(Theme.textMeta) }
            } footer: {
                Text("Undoes items you cleared while saving to Calendar is switched off. Calendar isn't touched.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Test tools")
        .navigationBarTitleDisplayMode(.inline)
    }
}
