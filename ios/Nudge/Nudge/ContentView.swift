// ContentView.swift — Nudge (iOS)
// StudyTrack-style: monochrome tinted, big left-aligned header, flat cards,
// and a text bottom-tab bar (Today · Upcoming · Lists · Search).

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NudgeStore
    @EnvironmentObject var sync: RemindersSync
    @EnvironmentObject var notifier: NotificationManager
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab = 0
    @State private var showAdd = false
    @State private var editingReminder: Reminder?
    @State private var showTriage = false
    @State private var showSettings = false
    @State private var collapsed: Set<String> = []
    @State private var search = ""
    @State private var listFilter: ReminderList?
    @State private var autoClaudeURL: IdentifiableURL?
    @State private var preparingClaude = false
    @State private var shown = false
    @State private var rescheduleResult: RescheduleResult?
    @State private var didLoad = false
    @State private var stuckCount = 0
    @State private var showCompleted = false
    @State private var isLocked = false
    @State private var signingDaysLeft: Int?
    @State private var rescheduleTarget: Reminder?
    @State private var showTimetable = false
    @State private var smartCollection: SmartCollection?
    @State private var showRoutineCheckin = false
    @State private var routineLapsed: [Reminder] = []
    @State private var routineStepUps: [Reminder] = []
    @Namespace private var tabNS

    private let tabs: [(name: String, icon: String)] = [
        ("Home", "square.grid.2x2"), ("Today", "tray.full"), ("Upcoming", "calendar"),
        ("Lists", "square.stack.3d.up"), ("Search", "magnifyingglass")
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if let d = signingDaysLeft, d <= 2 { expiryBanner(d) }
                ScrollView {
                    VStack(alignment: .leading, spacing: settings.compact ? 14 : 20) {
                        switch tab {
                        case 0: dashboardTab
                        case 1: todayTab
                        case 2: upcomingTab
                        case 3: listsTab
                        default: searchTab
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                    .animation(Theme.spring, value: store.reminders)
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity))
                }
            }

            bottomBar
        }
        .overlay(alignment: .bottomTrailing) {
            if tab <= 2 { fab.padding(.trailing, 20).padding(.bottom, 92) }
        }
        .overlay(alignment: .bottom) {
            if let d = store.recentlyDeleted { undoToast(d) }
        }
        .animation(Theme.spring, value: store.recentlyDeleted)
        .overlay { if preparingClaude { preparingOverlay } }
        .sheet(isPresented: $showAdd) { AddReminderView(editing: nil).environmentObject(store) }
        .sheet(item: $editingReminder) { r in AddReminderView(editing: r).environmentObject(store) }
        .sheet(isPresented: $showSettings) {
            SyncSettingsView().environmentObject(sync).environmentObject(notifier)
                .environmentObject(settings).environmentObject(store)
        }
        .sheet(item: $listFilter) { l in
            FilteredListView(list: l).environmentObject(store).environmentObject(settings)
        }
        .sheet(item: $smartCollection) { c in
            SmartCollectionView(collection: c).environmentObject(store).environmentObject(settings)
        }
        .fullScreenCover(isPresented: $showTriage) {
            TriageView(onSmartReschedule: {
                showTriage = false
                let plan = store.planSmartReschedule()
                if !plan.isEmpty { rescheduleResult = RescheduleResult(changes: plan, auto: false) }
            }).environmentObject(store)
        }
        .sheet(item: $autoClaudeURL) { SafariView(url: $0.url, tint: Theme.accent) }
        .sheet(item: $rescheduleResult) { SmartReschedulePreviewView(proposed: $0.changes).environmentObject(store) }
        .sheet(isPresented: $showTimetable) { TimetableView().environmentObject(store) }
        .sheet(isPresented: $showCompleted) { CompletedHistoryView().environmentObject(store) }
        .sheet(item: $rescheduleTarget) { r in RescheduleOptionsView(reminder: r).environmentObject(store) }
        .sheet(isPresented: $showRoutineCheckin) {
            RoutineCheckInView(lapsed: routineLapsed, stepUps: routineStepUps).environmentObject(store)
        }
        .tint(Theme.accent)
        .task {
            guard !didLoad else { return }
            didLoad = true
            LockShield.shared.onUnlock = { attemptUnlock() }
            if settings.appLock { lock() }
            signingDaysLeft = SigningInfo.daysLeft
            withAnimation(Theme.spring) { shown = true }
            if router.pendingQuickAdd { router.pendingQuickAdd = false; showAdd = true }
            await store.refresh()
            stuckCount = store.stuckCount()
            await sync.syncNow(); await notifier.reschedule()
            maybeRoutineCheckin()
        }
        .task {
            // Live-ish polling: pull cloud changes (reminders added on the web app or
            // another device) every 15s so they appear without a force-quit/relaunch.
            // iOS suspends this task while backgrounded; refresh() no-ops when nothing
            // changed and won't clobber un-pushed local edits.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                // Don't pull/re-render while the user is in the add/edit sheet — a
                // mid-edit store change can drop the title field's keyboard focus.
                if showAdd || editingReminder != nil || showSettings { continue }
                await store.refresh()
                stuckCount = store.stuckCount()
            }
        }
        .onChange(of: scenePhase) { _, p in
            switch p {
            case .inactive:
                // Blur immediately so the iOS app-switcher snapshot never shows content.
                // Skipped on Mac: there .inactive fires on every window-focus loss
                // (e.g. cmd-tab), which would flash the blur constantly.
                #if !targetEnvironment(macCatalyst)
                if settings.appLock { LockShield.shared.show(interactive: isLocked) }
                #endif
            case .background:
                if settings.appLock { isLocked = true; LockShield.shared.show(interactive: true) }
            case .active:
                if isLocked { attemptUnlock() } else { LockShield.shared.hide() }
                if didLoad {
                    Task { await store.refresh(); stuckCount = store.stuckCount()
                           await sync.syncNow(); await notifier.reschedule()
                           maybeRoutineCheckin() }
                }
            @unknown default: break
            }
        }
        .onChange(of: store.reminders) { _, _ in stuckCount = store.stuckCount() }
        .onChange(of: showTriage) { _, open in if !open { stuckCount = store.stuckCount() } }
        .onChange(of: router.pendingQuickAdd) { _, v in if v { router.pendingQuickAdd = false; showAdd = true } }
        .onChange(of: router.pendingShopping) { _, v in if v { router.pendingShopping = false; openShopping() } }
        .onChange(of: router.pendingReschedule) { _, id in
            guard let id, let r = store.reminders.first(where: { $0.id == id }) else { return }
            router.pendingReschedule = nil
            rescheduleTarget = r
        }
        .onChange(of: router.pendingClaudePrompt) { _, prompt in
            guard let prompt else { return }
            router.pendingClaudePrompt = nil; preparingClaude = true
            Task {
                let polished = await PromptPolisher.polish(prompt)
                UIPasteboard.general.string = polished
                try? await Task.sleep(nanoseconds: 400_000_000)
                if let u = ClaudeLink.url(for: polished) { autoClaudeURL = IdentifiableURL(url: u) }
                preparingClaude = false
            }
        }
    }

    // MARK: - Header (StudyTrack style)

    private var header: some View {
        let stats = todayStats
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.system(.largeTitle, design: .default).weight(.bold))
                        .foregroundStyle(Theme.textMain)
                    Text(headerSubtitle.uppercased())
                        .font(.caption.weight(.semibold)).tracking(0.6)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                HStack(spacing: 10) {
                    // Always present so Triage is findable; pulses coral when items are stuck.
                    iconButton(stuckCount > 0 ? "exclamationmark.triangle.fill" : "checklist",
                               pulse: stuckCount > 0) { showTriage = true }
                    iconButton("calendar.day.timeline.left") { showTimetable = true }
                    iconButton("gearshape") { showSettings = true }
                }
            }
            if tab == 0 {
                let actionable = store.overdueCount() > 0 || stuckCount > 0
                Button { if actionable { showTriage = true } } label: {
                    HStack(spacing: 5) {
                        Text(statusLine(stats)).font(.subheadline).foregroundStyle(Theme.textMeta)
                        if actionable {
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!actionable)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func undoToast(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trash").font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Text("Reminder deleted").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Spacer(minLength: 12)
            Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); store.undoDelete() } label: {
                Text("Undo").font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(Theme.textMain.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        .cardElevation(14, y: 5, opacity: 0.2)
        .padding(.horizontal, 24).padding(.bottom, 100)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: r.id) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            store.finalizeDelete()
        }
    }

    private func iconButton(_ name: String, pulse: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pulse ? Theme.coral : Theme.textMain)
                .symbolEffect(.pulse, isActive: pulse)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private var headerTitle: String {
        switch tab {
        case 0: return greeting
        case 1: return "Today"
        case 2: return "Upcoming"
        case 3: return "Lists"
        default: return "Search"
        }
    }
    private var headerSubtitle: String {
        switch tab {
        case 0: return Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
        case 1: return "What's due"
        case 2: return "What's coming up"
        case 3: return "\(store.lists.count) lists"
        default: return "Find a reminder"
        }
    }
    private func statusLine(_ s: (done: Int, total: Int)) -> String {
        let od = store.overdueCount()
        if od > 0 { return "🔴 \(od) overdue · spread them below" }
        if stuckCount > 0 { return "⚠︎ \(stuckCount) you keep avoiding · tap to review" }
        if s.total == 0 { return "Nothing due today — you're clear." }
        return "\(s.done) of \(s.total) done today"
    }

    // MARK: - Home dashboard

    @ViewBuilder private var dashboardTab: some View {
        progressHero.popIn(0)
        if let nu = nextUp { nextUpCard(nu).popIn(1) }

        // Pay day: surface the buy list right on Home (tickable), capped so it stays tidy.
        if Payday.isToday() {
            let buys = store.buyReminders()
            if !buys.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "cart.fill").font(.caption2).foregroundStyle(Theme.accent)
                    Text("PAY DAY · \(buys.count) TO BUY").font(.caption.weight(.bold))
                        .tracking(0.8).foregroundStyle(Theme.textMeta)
                    Spacer()
                    Button("Shopping") { openShopping() }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                .padding(.top, 4).padding(.leading, 2).popIn(1)
                let cap = 4
                ForEach(Array(buys.prefix(cap).enumerated()), id: \.element.id) { i, r in
                    ReminderCardView(reminder: r) { editingReminder = r }.popIn(2 + i)
                }
                if buys.count > cap {
                    Button { openShopping() } label: {
                        Text("+ \(buys.count - cap) more in Shopping")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }.padding(.top, 2)
                }
            }
        }

        let pinned = store.pinnedReminders()
        if !pinned.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent)
                Text("PINNED").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                Spacer()
            }
            .padding(.top, 4).padding(.leading, 2)
            .popIn(2)
            ForEach(Array(pinned.enumerated()), id: \.element.id) { i, r in
                ReminderCardView(reminder: r) { editingReminder = r }.popIn(3 + i)
            }
        }

        let od = store.overdueCount()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            statCard("Overdue", od, "exclamationmark.triangle", od > 0 ? Theme.coral : Theme.accent) { if od > 0 { switchTab(1) } }
            statCard("Due today", dueTodayCount, "sun.max", Theme.accent) { switchTab(1) }
            statCard("This week", thisWeekCount, "calendar", Theme.accent) { switchTab(2) }
            statCard("Done today", todayStats.done, "checkmark.circle", Theme.sage) { showCompleted = true }
        }
        .popIn(2)

        if od > 0 { smartRescheduleButton.popIn(3) }

        let todays = store.todayReminders()
        if !todays.isEmpty {
            HStack {
                Text("TODAY").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                Spacer()
                Button("See all") { switchTab(1) }.font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .padding(.top, 4).padding(.leading, 2)
            .popIn(4)
            // Home shows a short preview of today; "See all" / "+N more" opens the
            // full Today tab. A small fixed cap is predictable across window sizes.
            let fit = 6
            ForEach(Array(todays.prefix(fit).enumerated()), id: \.element.id) { i, r in
                ReminderCardView(reminder: r) { editingReminder = r }.popIn(5 + i)
            }
            if todays.count > fit {
                Button { switchTab(1) } label: {
                    Text("+ \(todays.count - fit) more")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                .padding(.top, 2)
            }
        }
    }

    private func switchTab(_ i: Int) { withAnimation(Theme.spring) { tab = i } }

    private func openShopping() {
        if let l = store.lists.first(where: { $0.id == "shopping" }) { listFilter = l }
    }

    private var nextUp: Reminder? {
        let now = Date()
        return store.open()
            .compactMap { r -> (Reminder, Date)? in
                guard let d = parseDate(r.dueDate), d > now else { return nil }
                return (r, d)
            }
            .min { $0.1 < $1.1 }?.0
    }

    private func nextUpCard(_ r: Reminder) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill").font(.caption).foregroundStyle(Theme.accent)
                    Text("NEXT UP").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                    if let lbl = dueLabel(r) { Text("· " + lbl).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                }
                Text(displayTitle(r)).font(.title3.weight(.bold)).foregroundStyle(Theme.textMain).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editingReminder = r }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(Theme.spring) { store.toggleComplete(r) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(PressableStyle(scale: 0.85))
        }
        .padding(18)
        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statCard(_ label: String, _ value: Int, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Theme.textMeta)
                    Spacer()
                    Image(systemName: icon).font(.caption).foregroundStyle(color)
                }
                Text("\(value)").font(.system(size: 30, weight: .heavy)).foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private var dueTodayCount: Int {
        let cal = Calendar.current
        return store.open().filter { if let d = parseDate($0.dueDate) { return cal.isDateInToday(d) }; return false }.count
    }
    private var thisWeekCount: Int {
        let now = Date(); let wk = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        return store.open().filter { if let d = parseDate($0.dueDate) { return d > now && d <= wk }; return false }.count
    }

    private var smartRescheduleButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            let plan = store.planSmartReschedule()
            if !plan.isEmpty { rescheduleResult = RescheduleResult(changes: plan, auto: false) }
        } label: {
            Label("Smart Reschedule overdue", systemImage: "sparkles")
                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(13)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Today tab

    @ViewBuilder private var todayTab: some View {
        if store.overdueCount() > 0 { smartRescheduleButton }
        let secs = store.sections().filter { $0.id == "overdue" || $0.id == "today" }
        if secs.isEmpty { emptyCard("checkmark.circle.fill", "Nothing due today", "You're on top of it.") }
        ForEach(secs) { sectionView($0) }
    }

    private var progressHero: some View {
        let s = todayStats
        let frac = s.total > 0 ? Double(s.done) / Double(s.total) : 0
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                Text(s.total == 0 ? "All clear" : "\(s.done)/\(s.total) done")
                    .font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.textMain)
                    .contentTransition(.numericText())
            }
            Spacer()
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 7)
                Circle().trim(from: 0, to: max(0.001, frac))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Theme.spring, value: frac)
            }.frame(width: 54, height: 54)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Upcoming tab

    @ViewBuilder private var upcomingTab: some View {
        // Lists the user pinned as their own sections (in their chosen order).
        let chosen = settings.upcomingSections.compactMap { id in store.lists.first { $0.id == id } }
        let chosenIds = Set(chosen.map { $0.id })
        let byDate: (Reminder, Reminder) -> Bool = {
            (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture)
        }
        // Default Upcoming + No-date buckets, minus anything already shown in a pinned list.
        let defaults = store.sections().filter { $0.id == "upcoming" || $0.id == "nodate" }
            .map { NudgeStore.ReminderSection(id: $0.id, title: $0.title,
                                              items: $0.items.filter { !chosenIds.contains($0.listIdOrDefault) }) }
            .filter { !$0.items.isEmpty }
        let cal = Calendar.current
        let pinned: [NudgeStore.ReminderSection] = chosen.compactMap { l in
            let items = store.open().filter { r in
                guard r.listIdOrDefault == l.id, !store.isOverdue(r) else { return false }
                if parseDate(r.snoozedUntil).map({ $0 > Date() }) == true { return false }   // snoozed → Upcoming default bucket
                if parseDate(r.dueDate).map({ cal.isDateInToday($0) }) == true { return false } // today → Today tab
                return true
            }.sorted(by: byDate)
            return items.isEmpty ? nil : NudgeStore.ReminderSection(id: "list-\(l.id)", title: l.name, items: items)
        }
        if pinned.isEmpty && defaults.isEmpty {
            emptyCard("calendar", "Nothing upcoming", "New reminders will show here.")
        }
        ForEach(pinned) { sectionView($0) }
        ForEach(defaults) { sectionView($0) }
    }

    // MARK: - Lists tab

    private let listGrid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    @ViewBuilder private var listsTab: some View {
        // Smart Collections — auto-slices of your reminders by attribute, not manual
        // folders. Only the ones that currently have items show up.
        let collections = SmartCollection.all.filter { c in store.open().contains(where: c.match) }
        if !collections.isEmpty {
            listHeader("SMART COLLECTIONS")
            LazyVGrid(columns: listGrid, spacing: 12) {
                ForEach(Array(collections.enumerated()), id: \.element.id) { i, c in
                    let n = store.open().filter(c.match).count
                    Button { smartCollection = c } label: { collectionCard(c, count: n) }
                        .buttonStyle(PressableStyle(scale: 0.97))
                        .popIn(i)
                }
            }
        }

        listHeader("YOUR LISTS").padding(.top, collections.isEmpty ? 0 : 6)
        LazyVGrid(columns: listGrid, spacing: 12) {
            ForEach(Array(store.lists.enumerated()), id: \.element.id) { i, l in
                Button { listFilter = l } label: { listCard(l) }
                    .buttonStyle(PressableStyle(scale: 0.97))
                    .popIn(i)
            }
        }

        Button { showCompleted = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                Text("Completed").font(.body.weight(.medium)).foregroundStyle(Theme.textMain)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textMeta)
            }
            .padding(15)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .padding(.top, 8)
    }

    private func listHeader(_ t: String) -> some View {
        Text(t).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2)
    }

    private func collectionCard(_ c: SmartCollection, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: c.icon).font(.system(size: 16, weight: .bold)).foregroundStyle(c.color)
                    .frame(width: 34, height: 34).background(c.color.opacity(0.15), in: Circle())
                Spacer()
                Text("\(count)").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.textMain)
            }
            Text(c.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain).lineLimit(1)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func listCard(_ l: ReminderList) -> some View {
        let color = Color(hex: l.color)
        let inList = store.reminders.filter { $0.listIdOrDefault == l.id }
        let open = inList.filter { !($0.completed ?? false) }.count
        let total = inList.count
        let done = total - open
        let frac = total > 0 ? Double(done) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                Circle().fill(color).frame(width: 14, height: 14)
                Spacer()
                Text("\(open)").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.textMain)
            }
            Text(l.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(color).frame(width: max(0, geo.size.width * frac))
                }
            }
            .frame(height: 5)
            Text(total == 0 ? "Empty" : "\(done)/\(total) done")
                .font(.caption2.weight(.medium)).foregroundStyle(Theme.textMeta)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    // MARK: - Search tab

    @ViewBuilder private var searchTab: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textMeta)
            TextField("Search reminders", text: $search)
            if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMeta) } }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            let results = store.open().filter { displayTitle($0).lowercased().contains(q) }
            if results.isEmpty {
                emptyCard("magnifyingglass", "No matches", "Nothing matches “\(search)”.")
                    .popIn()
            } else {
                VStack(alignment: .leading, spacing: settings.compact ? 8 : 10) {
                    HStack(spacing: 6) {
                        Text("\(results.count) match\(results.count == 1 ? "" : "es")")
                            .font(.caption.weight(.bold)).tracking(0.4).foregroundStyle(Theme.textMeta)
                        Spacer()
                    }
                    .padding(.leading, 2)
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, r in
                        ReminderCardView(reminder: r) { editingReminder = r }
                            .popIn(i)
                    }
                }
                // Rebuild on each query so every visible result pops in fresh.
                .id(q)
            }
        }
    }

    // MARK: - Shared bits

    private func sectionView(_ section: NudgeStore.ReminderSection) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        let isOverdue = section.id == "overdue"
        return VStack(alignment: .leading, spacing: settings.compact ? 8 : 10) {
            Button {
                withAnimation(Theme.spring) {
                    if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(section.title.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
                        .foregroundStyle(isOverdue ? Theme.coral : Theme.textMeta)
                    Text("\(section.items.count)").font(.caption2.weight(.bold))
                        .contentTransition(.numericText())
                        .foregroundStyle(isOverdue ? .white : Theme.textMeta)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(isOverdue ? AnyShapeStyle(Theme.coral) : AnyShapeStyle(Theme.surfaceAlt), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.leading, 2).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed {
                ForEach(section.items) { r in
                    ReminderCardView(reminder: r) { editingReminder = r }
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.9).combined(with: .opacity)))
                }
            }
        }
    }

    private func emptyCard(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Theme.accent)
            Text(title).font(.headline).foregroundStyle(Theme.textMain)
            Text(sub).font(.subheadline).foregroundStyle(Theme.textMeta)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    private var fab: some View {
        Button {
            showAdd = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(reverseText)
                .frame(width: 58, height: 58)
                .background(Theme.accent, in: Circle())
                .cardElevation(12, y: 4, opacity: 0.18)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .scaleEffect(shown ? 1 : 0.6).opacity(shown ? 1 : 0)
        .animation(Theme.bouncy, value: shown)
    }

    private var bottomBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in
                let active = tab == i
                Button { withAnimation(Theme.spring) { tab = i } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon)
                            .font(.system(size: 17, weight: active ? .bold : .regular))
                            .scaleEffect(active ? 1.1 : 1)
                            .symbolEffect(.bounce, value: active)
                        Text(t.name).font(.caption2.weight(active ? .bold : .medium))
                    }
                    .foregroundStyle(active ? Theme.accent : Theme.textMeta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.accentSoft)
                                .matchedGeometryEffect(id: "tabSel", in: tabNS)
                        }
                    }
                    .contentShape(Rectangle())   // whole cell is tappable, not just the icon/label
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8).padding(.bottom, 2).padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .top)
    }

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Preparing Claude…").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
            }
            .padding(24).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // reverse text colour for on-accent (white on dark accent, dark on light accent) — accents are dark, so white.
    private var reverseText: Color { .white }

    private func expiryBanner(_ days: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(days <= 0 ? "App access expires today" : "App expires in \(days) day\(days == 1 ? "" : "s")")
                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text("Run “Reinstall Nudge” on your Mac to keep it working.")
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.coral, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 18).padding(.bottom, 8)
    }

    /// Lock the app: cover the screen (over any open sheet) and prompt to unlock.
    private func lock() {
        isLocked = true
        LockShield.shared.show(interactive: true)
        attemptUnlock()
    }

    private func attemptUnlock() {
        Task {
            if await BiometricLock.authenticate() {
                withAnimation(Theme.spring) { isLocked = false }
                LockShield.shared.hide()
                maybeRoutineCheckin()   // was skipped while locked — try now we're in
            }
        }
    }

    /// First app-open of the day: if a nightly routine lapsed (or an Epiduo step-up is
    /// due), present the check-in once. Skipped while locked (re-tried after unlock).
    private func maybeRoutineCheckin() {
        guard !isLocked, !showRoutineCheckin else { return }
        let todayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        guard UserDefaults.standard.string(forKey: "routineCheckinDay") != todayKey else { return }
        let lapsed = store.lapsedRoutinesForCheckin()
        let stepUps = store.routinesDueForStepUpAsk()
        guard !lapsed.isEmpty || !stepUps.isEmpty else { return }
        routineLapsed = lapsed
        routineStepUps = stepUps
        UserDefaults.standard.set(todayKey, forKey: "routineCheckinDay")
        showRoutineCheckin = true
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 3..<6:   return "Early Morning"
        case 6..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default:      return "Late Night"
        }
    }
    private var todayStats: (done: Int, total: Int) {
        let cal = Calendar.current
        var done = 0, openToday = 0
        for r in store.reminders {
            if let ca = parseDate(r.completedAt), cal.isDateInToday(ca) { done += 1; continue }
            if !(r.completed ?? false), let d = parseDate(r.dueDate), cal.isDateInToday(d) { openToday += 1 }
        }
        return (done, done + openToday)
    }
}

// MARK: - Filtered list (from the Lists tab)

/// A dynamic, attribute-based slice of reminders — the "new way to use lists".
/// Unlike a manual `ReminderList`, membership is computed by a predicate.
struct SmartCollection: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let match: (Reminder) -> Bool

    static var all: [SmartCollection] {
        [
            SmartCollection(id: "high", title: "High Priority", icon: "flag.fill", color: Theme.coral) {
                $0.priorityOrNormal == "high"
            },
            SmartCollection(id: "scheduled", title: "Scheduled", icon: "calendar", color: Theme.accent) {
                $0.dueDate != nil
            },
            SmartCollection(id: "repeating", title: "Repeating", icon: "repeat", color: Theme.accent) {
                $0.recurrence != nil && $0.recurrence?.freq != "none"
            },
            SmartCollection(id: "links", title: "With Links", icon: "link", color: Theme.accent) {
                ($0.url?.isEmpty == false)
            },
            SmartCollection(id: "nodate", title: "No Date", icon: "tray", color: Theme.textMeta) {
                $0.dueDate == nil
            },
        ]
    }
}

struct SmartCollectionView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let collection: SmartCollection
    @State private var editingReminder: Reminder?

    private var items: [Reminder] {
        let prank: (Reminder) -> Int = { $0.priorityOrNormal == "high" ? 0 : $0.priorityOrNormal == "low" ? 2 : 1 }
        return store.open().filter(collection.match).sorted {
            let ra = prank($0), rb = prank($1)
            if ra != rb { return ra < rb }
            return (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty {
                        Text("Nothing here right now.").font(.subheadline).foregroundStyle(Theme.textMeta)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, r in
                            ReminderCardView(reminder: r) { editingReminder = r }.popIn(i)
                        }
                    }
                }
                .padding(16)
                .animation(Theme.spring, value: store.reminders)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(collection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingReminder) { r in AddReminderView(editing: r).environmentObject(store) }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }
}

struct FilteredListView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let list: ReminderList
    @State private var editingReminder: Reminder?
    @State private var sectionNames: [String] = []
    @State private var dropTarget: String?
    @State private var showAddSection = false
    @State private var newSectionName = ""

    private var items: [Reminder] { store.open().filter { $0.listIdOrDefault == list.id } }

    private var allSections: [String] {
        var names = sectionNames
        for r in items { if let s = r.section, !s.isEmpty, !names.contains(s) { names.append(s) } }
        return names
    }
    private func rows(in section: String?) -> [Reminder] {
        items.filter { (($0.section?.isEmpty == false) ? $0.section : nil) == section }
             .sorted { (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    block(title: nil)                              // ungrouped, at top
                    ForEach(allSections, id: \.self) { block(title: $0) }
                    Button { newSectionName = ""; showAddSection = true } label: {
                        Label("Add section", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 2)
                    if items.isEmpty {
                        Text("Nothing in this list.").font(.subheadline).foregroundStyle(Theme.textMeta)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(16)
                .animation(Theme.spring, value: store.reminders)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(list.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingReminder) { r in AddReminderView(editing: r).environmentObject(store) }
            .onAppear { sectionNames = SectionStore.names(for: list.id) }
            .alert("New section", isPresented: $showAddSection) {
                TextField("Section name", text: $newSectionName)
                Button("Add") {
                    SectionStore.add(newSectionName, to: list.id)
                    sectionNames = SectionStore.names(for: list.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Drag reminders into it once it's created.") }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }

    @ViewBuilder private func block(title: String?) -> some View {
        let list_ = rows(in: title)
        let key = title ?? "__ungrouped__"
        // Named sections always show (to drop into). The ungrouped block shows
        // only when it has items, or when sections exist (so you can drop back).
        if title != nil || !list_.isEmpty || !allSections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let t = title {
                    HStack(spacing: 7) {
                        Text(t.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent)
                        Text("\(list_.count)").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.surfaceAlt, in: Capsule())
                        Spacer()
                        Menu {
                            Button("Rename…") { /* future */ }
                            Button("Delete section", role: .destructive) {
                                for r in list_ { store.setSection(r.id, to: nil) }
                                SectionStore.remove(t, from: list.id)
                                sectionNames = SectionStore.names(for: list.id)
                            }
                        } label: { Image(systemName: "ellipsis").foregroundStyle(Theme.textMeta).padding(.horizontal, 4) }
                    }
                    .padding(.leading, 2)
                }
                if list_.isEmpty {
                    Text("Drag reminders here").font(.caption).foregroundStyle(Theme.textMeta)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                } else {
                    ForEach(list_) { r in
                        ReminderCardView(reminder: r) { editingReminder = r }
                            .draggable(r.id)
                    }
                }
            }
            .padding(8)
            .background((dropTarget == key ? Theme.accentSoft : Color.clear),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .dropDestination(for: String.self) { ids, _ in
                for id in ids { store.setSection(id, to: title) }
                return true
            } isTargeted: { t in dropTarget = t ? key : nil }
        }
    }
}

// MARK: - Display helpers

func displayTitle(_ r: Reminder) -> String {
    let stripped = r.title
        .replacingOccurrences(of: "#[\\p{L}0-9_-]+", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    return stripped.isEmpty ? r.title : stripped
}

func dueLabel(_ r: Reminder) -> String? {
    guard let d = parseDate(r.dueDate) else { return nil }
    let cal = Calendar.current
    let hasTime = r.hasTime ?? false
    let f = DateFormatter()
    // Only surface a foreign-timezone label when the pinned zone actually differs
    // from where the user is now. Same zone → show it like any normal local time.
    if let tzId = r.tz, let tzone = TimeZone(identifier: tzId), hasTime,
       tzId != TimeZone.current.identifier {
        f.timeZone = tzone; f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d) + " " + tzCity(tzId)
    }
    if cal.isDateInToday(d) { f.dateFormat = hasTime ? "'Today,' HH:mm" : "'Today'" }
    else if cal.isDateInTomorrow(d) { f.dateFormat = hasTime ? "'Tomorrow,' HH:mm" : "'Tomorrow'" }
    else { f.dateFormat = hasTime ? "d MMM, HH:mm" : "d MMM" }
    return f.string(from: d)
}

#Preview {
    ContentView()
        .environmentObject(NudgeStore()).environmentObject(RemindersSync())
        .environmentObject(NotificationManager()).environmentObject(AppSettings())
}
