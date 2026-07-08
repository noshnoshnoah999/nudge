// AddReminderView.swift — Nudge (iOS)
// Add or edit a reminder, themed to match the app (warm tinted cards, not the
// stock grey Form). Pass `editing` to edit an existing one.

import SwiftUI
import PhotosUI

struct AddReminderView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    var editing: Reminder?

    // Local image attachments (stored on-device under the reminder id).
    @State private var draftId = "r" + String(UUID().uuidString.prefix(12))
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newImages: [(id: UUID, data: Data)] = []
    @State private var existingURLs: [URL] = []
    @State private var removedURLs: Set<URL> = []
    @State private var previewImage: UIImage?
    private var reminderId: String { editing?.id ?? draftId }

    struct AttachedImage: Identifiable { let id: String; let image: UIImage; let url: URL? }
    private var visibleImages: [AttachedImage] {
        var out: [AttachedImage] = []
        for u in existingURLs where !removedURLs.contains(u) {
            if let im = ImageStore.image(u) { out.append(.init(id: u.path, image: im, url: u)) }
        }
        for n in newImages {
            if let im = UIImage(data: n.data) { out.append(.init(id: "new-" + n.id.uuidString, image: im, url: nil)) }
        }
        return out
    }
    private func remove(_ img: AttachedImage) {
        if let u = img.url { removedURLs.insert(u) }
        else { newImages.removeAll { "new-" + $0.id.uuidString == img.id } }
    }

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var hasTime = true
    enum SchedExpand { case none, date, time }   // which inline picker is open (accordion)
    @State private var schedExpand: SchedExpand = .none
    @State private var listId = "reminders"
    @State private var priority = "normal"
    @State private var pinned = false
    @State private var urgent = false
    @State private var earlyAlerts: [Int] = []   // early-reminder offsets, minutes before due
    @State private var showCustomEarly = false
    @State private var customEarlyVal = 1
    @State private var customEarlyUnit = 1440    // minutes per unit (days default)
    @State private var subtasks: [Subtask] = []
    @State private var newSubtask = ""
    @State private var routine = false           // nightly routine → morning check-in
    @State private var escalation: [EscalationStep] = []
    @State private var askToReview = false       // adaptive "ready to step up?" prompt
    @State private var repeatFreq = "none"
    @State private var repeatInterval = 1
    @State private var hasUntil = false
    @State private var until = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var tz = ""
    @State private var url = ""
    @State private var location = ""
    @State private var lat: Double?
    @State private var lng: Double?
    @State private var showLocationPicker = false
    @FocusState private var titleFocused: Bool
    @State private var buyRuleApplied = false   // so the live "buy" rule fires once per appearance of the word
    @State private var claudeRuleApplied = false   // same, for the "Claude - " → Claude list rule
    @State private var showConflictAlert = false
    @State private var conflictMsg: String?
    @FocusState private var notesFocused: Bool

    private let zones: [(String, String)] = [
        ("Local (device)", ""),
        ("UK — London", "Europe/London"),
        ("Japan — Tokyo", "Asia/Tokyo"),
        ("US East — New York", "America/New_York"),
        ("US West — Los Angeles", "America/Los_Angeles"),
        ("Europe — Paris", "Europe/Paris"),
        ("UAE — Dubai", "Asia/Dubai"),
        ("Singapore", "Asia/Singapore"),
        ("Australia — Sydney", "Australia/Sydney")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Title — plain (single-line) TextField: a vertical-axis TextField
                    // inside a ScrollView won't become first responder on iOS (no keyboard
                    // on tap), though it works on Mac Catalyst. This focuses reliably.
                    TextField("What do you need to remember?", text: $title, axis: .vertical)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textMain)
                        .lineLimit(1...8)        // grows down as the title gets longer
                        .focused($titleFocused)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                        // Belt-and-braces: also force focus on tap (doesn't steal the tap).
                        // Gated on !titleFocused so this doesn't re-fire (and race the
                        // system's double-tap-to-select recognizer) once the field is
                        // already focused — that collision was breaking word selection
                        // when editing an existing reminder's title on iOS.
                        .simultaneousGesture(TapGesture().onEnded { if !titleFocused { titleFocused = true } })

                    // Schedule
                    section("When") {
                        schedRow("calendar", "Date", subtitle: hasDue ? relativeDateText(due) : nil,
                                 isOn: Binding(
                                    get: { hasDue },
                                    set: { on in withAnimation(Theme.spring) {
                                        hasDue = on
                                        schedExpand = on ? .date : .none
                                        if !on { hasTime = false }
                                    } }),
                                 onTap: {
                                    guard hasDue else { return }
                                    withAnimation(Theme.spring) { schedExpand = (schedExpand == .date) ? .none : .date }
                                 })
                        if hasDue {
                            if schedExpand == .date {
                                divider
                                MiniCalendar(date: $due)
                                    .padding(.vertical, 6)
                            }
                            divider
                            schedRow("clock", "Time", subtitle: hasTime ? timeText(due) : nil,
                                     isOn: Binding(
                                        get: { hasTime },
                                        set: { on in withAnimation(Theme.spring) {
                                            hasTime = on
                                            schedExpand = on ? .time : (schedExpand == .time ? .none : schedExpand)
                                        } }),
                                     onTap: {
                                        guard hasTime else { return }
                                        withAnimation(Theme.spring) { schedExpand = (schedExpand == .time) ? .none : .time }
                                     })
                            if hasTime && schedExpand == .time {
                                divider
                                timePresetRow
                                DatePicker("", selection: $due, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel)
                                    .tint(Theme.accent).labelsHidden()
                                    .frame(maxWidth: .infinity)
                            }
                            divider
                            menuRow("Repeat", "repeat") {
                                Picker("Repeat", selection: $repeatFreq.animation(Theme.spring)) {
                                    Text("Never").tag("none")
                                    Text("Hourly").tag("hourly")
                                    Text("Daily").tag("daily")
                                    Text("Weekly").tag("weekly")
                                    Text("Monthly").tag("monthly")
                                    Text("Yearly").tag("yearly")
                                }.labelsHidden().tint(Theme.accent)
                            }
                            if repeatFreq != "none" {
                                divider
                                Stepper(value: $repeatInterval, in: stepRange) {
                                    rowLabel("Every \(repeatInterval) \(unitLabel)", "number")
                                }
                                .tint(Theme.accent).padding(.vertical, 6)
                                divider
                                toggleRow("End repeat", systemImage: "calendar.badge.exclamationmark",
                                          isOn: $hasUntil.animation(Theme.spring))
                                if hasUntil {
                                    divider
                                    DatePicker(selection: $until, displayedComponents: [.date]) {
                                        rowLabel("Ends", "flag.checkered")
                                    }
                                    .tint(Theme.accent).padding(.vertical, 6)
                                }
                            }
                            divider
                            toggleRow("Nightly check-in", systemImage: "moon.stars",
                                      isOn: $routine.animation(Theme.spring))
                            if routine {
                                divider
                                routineEditor
                            }
                            if hasTime {
                                divider
                                earlyAlertsEditor
                                divider
                                menuRow("Time zone", "globe") {
                                    Picker("Time zone", selection: $tz) {
                                        ForEach(zones, id: \.1) { Text($0.0).tag($0.1) }
                                    }.labelsHidden().tint(Theme.accent)
                                }
                            }
                        }
                    }

                    // Organise
                    section("Organise") {
                        menuRow("List", "tray") {
                            Picker("List", selection: $listId) {
                                ForEach(store.lists) { l in Text(l.name).tag(l.id) }
                            }.labelsHidden().tint(Theme.accent)
                        }
                        divider
                        menuRow("Priority", "flag") {
                            Picker("Priority", selection: $priority) {
                                Text("Low").tag("low"); Text("Normal").tag("normal"); Text("High").tag("high")
                            }.labelsHidden().tint(Theme.accent)
                        }
                        divider
                        menuRow("Pin to Home", "pin") {
                            Toggle("", isOn: $pinned).labelsHidden().tint(Theme.accent)
                        }
                        #if !targetEnvironment(macCatalyst)
                        divider
                        menuRow("Urgent (alarm)", "alarm") {
                            Toggle("", isOn: $urgent).labelsHidden().tint(Theme.coral)
                        }
                        #endif
                    }

                    // Details
                    section("Details") {
                        HStack(spacing: 10) {
                            Image(systemName: "link").foregroundStyle(Theme.accent).frame(width: 22)
                            TextField("Link (https://…)", text: $url)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .foregroundStyle(Theme.textMain)
                        }.padding(.vertical, 12)
                        divider
                        Button { showLocationPicker = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent).frame(width: 22)
                                Text(location.isEmpty ? "Add location" : location)
                                    .foregroundStyle(location.isEmpty ? Theme.textMeta : Theme.textMain)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textMeta)
                            }.padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    // Photos
                    section("Photos") {
                        if !visibleImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(visibleImages) { img in
                                        Image(uiImage: img.image).resizable().scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .overlay(alignment: .topTrailing) {
                                                Button { remove(img) } label: {
                                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.5))
                                                }.padding(2)
                                            }
                                            .onTapGesture { previewImage = img.image }
                                    }
                                }.padding(.vertical, 8)
                            }
                            divider
                        }
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                            HStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled").foregroundStyle(Theme.accent).frame(width: 22)
                                Text("Add photos").foregroundStyle(Theme.textMain)
                            }.padding(.vertical, 12)
                        }
                    }

                    // Subtasks
                    section("Subtasks") {
                        ForEach($subtasks) { $s in
                            HStack(spacing: 10) {
                                Button { s.done.toggle() } label: {
                                    Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(s.done ? Theme.sage : Theme.textMeta).frame(width: 22)
                                }.buttonStyle(.plain)
                                TextField("Subtask", text: $s.title)
                                    .foregroundStyle(s.done ? Theme.textMeta : Theme.textMain)
                                    .strikethrough(s.done)
                                Button { subtasks.removeAll { $0.id == s.id } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.textMeta.opacity(0.6))
                                }.buttonStyle(.plain)
                            }.padding(.vertical, 9)
                            divider
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle").foregroundStyle(Theme.accent).frame(width: 22)
                            TextField("Add subtask", text: $newSubtask)
                                .foregroundStyle(Theme.textMain)
                                .onSubmit(addSubtask)
                        }.padding(.vertical, 12)
                    }

                    // Notes
                    section("Notes") {
                        TextField("Add notes…", text: $notes, axis: .vertical)
                            .lineLimit(2...6).foregroundStyle(Theme.textMain).padding(.vertical, 10)
                            .focused($notesFocused)
                            // Same gating as the title field above — see comment there.
                            .simultaneousGesture(TapGesture().onEnded { if !notesFocused { notesFocused = true } })
                    }

                    if let e = editing {
                        Button(role: .destructive) {
                            withAnimation(Theme.spring) { store.deleteReminder(e) }; dismiss()
                        } label: {
                            Label("Delete Reminder", systemImage: "trash")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.coral)
                                .frame(maxWidth: .infinity).padding(14)
                                .background(Theme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(18)
                .animation(Theme.spring, value: hasDue)
                .animation(Theme.spring, value: hasTime)
                .animation(Theme.spring, value: repeatFreq)
                .animation(Theme.spring, value: hasUntil)
            }
            .background(Theme.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            // Drop the keyboard when a date/time picker opens so it doesn't cover it.
            .onChange(of: schedExpand) { _, v in if v != .none { titleFocused = false } }
            // Live "buy" rule: the moment the title contains the word "buy", drop it into
            // Shopping (+ payday date) so the user sees it land there as they type —
            // no need to wait for Save. Fires once per appearance; re-arms if "buy" is
            // removed, and never fights a manual change made afterwards.
            .onChange(of: title) { _, newValue in
                guard editing == nil else { return }
                let hasBuy = newValue.range(of: "\\bbuy\\b", options: [.regularExpression, .caseInsensitive]) != nil
                if hasBuy && !buyRuleApplied {
                    buyRuleApplied = true
                    withAnimation(Theme.snappy) { applyBuyRule() }
                } else if !hasBuy {
                    buyRuleApplied = false
                }
                // Live "Claude" rule: a title starting "Claude - " files into the Claude list.
                let hasClaude = isClaudeTitle(newValue)
                if hasClaude && !claudeRuleApplied {
                    claudeRuleApplied = true
                    withAnimation(Theme.snappy) { applyClaudeRule() }
                } else if !hasClaude {
                    claudeRuleApplied = false
                }
            }
            .navigationTitle(editing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
            // Ask for alarm permission the moment Urgent is switched on, so the prompt always
            // appears (not only later, deep inside saving a future-timed reminder).
            .onChange(of: urgent) { _, on in
                if on, #available(iOS 26.0, *) { Task { await NudgeAlarms.authorize() } }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("You're busy then", isPresented: $showConflictAlert) {
                Button("Schedule anyway") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your calendar has \(conflictMsg ?? "an event") at that time.")
            }
            .onAppear(perform: load)
            .onChange(of: pickerItems) { _, items in
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { newImages.append((UUID(), data)) }
                    }
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { previewImage != nil }, set: { if !$0 { previewImage = nil } })) {
                if let img = previewImage { ImagePreview(image: img) { previewImage = nil } }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(initialName: location, initialLat: lat, initialLng: lng,
                                   onSelect: { n, la, lo in location = n; lat = la; lng = lo },
                                   onRemove: { location = ""; lat = nil; lng = nil })
            }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }

    // MARK: - Themed building blocks

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8)
                .foregroundStyle(Theme.accent).padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    private func rowLabel(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
            Text(text).foregroundStyle(Theme.textMain)
        }
    }

    private func toggleRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { rowLabel(title, systemImage) }
            .tint(Theme.accent).padding(.vertical, 10)
    }

    @ViewBuilder private func menuRow<C: View>(_ title: String, _ icon: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            rowLabel(title, icon)
            Spacer()
            control()
        }.padding(.vertical, 8)
    }

    private var stepRange: ClosedRange<Int> { repeatFreq == "hourly" ? 1...23 : 1...365 }

    private var unitLabel: String {
        switch repeatFreq {
        case "hourly":  return repeatInterval == 1 ? "hour" : "hours"
        case "daily":   return repeatInterval == 1 ? "day" : "days"
        case "weekly":  return repeatInterval == 1 ? "week" : "weeks"
        case "monthly": return repeatInterval == 1 ? "month" : "months"
        case "yearly":  return repeatInterval == 1 ? "year" : "years"
        default:        return ""
        }
    }

    private func load() {
        guard let r = editing else {
            if let first = store.lists.first { listId = first.id }
            hasDue = true; hasTime = true
            due = Date().addingTimeInterval(3600)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { titleFocused = true }
            return
        }
        title = r.title
        notes = r.notes ?? ""
        if let d = parseDate(r.dueDate) {
            hasDue = true; hasTime = r.hasTime ?? false
            if let tzId = r.tz, let tzone = TimeZone(identifier: tzId) {
                tz = tzId
                var cal = Calendar(identifier: .gregorian); cal.timeZone = tzone
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
                due = Calendar.current.date(from: comps) ?? d
            } else { due = d }
        }
        listId = r.listIdOrDefault
        priority = r.priorityOrNormal
        pinned = r.pinned ?? false
        urgent = r.urgent ?? false
        if let rec = r.recurrence, rec.freq != "none" {
            repeatFreq = rec.freq
            repeatInterval = max(1, rec.interval ?? 1)
            if let u = parseDate(rec.until) { hasUntil = true; until = u }
        }
        url = r.url ?? ""
        location = r.location ?? ""
        lat = r.lat; lng = r.lng
        earlyAlerts = r.earlyAlerts
        subtasks = r.subtasks ?? []
        routine = r.routine ?? false
        escalation = r.escalation ?? []
        askToReview = r.escalateAskNext != nil
        existingURLs = ImageStore.urls(for: r.id)
    }

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        subtasks.append(Subtask(id: "s" + String(UUID().uuidString.prefix(11)), title: t, done: false))
        newSubtask = ""
    }

    // Nightly routine editor: explainer + ordered escalating-frequency phases + the
    // adaptive "ask me to review" prompt.
    @ViewBuilder private var routineEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If you don't tick this the night it's due, Nudge asks \"did you do it last night?\" the next morning — Yes rolls it forward, or move it to another day.")
                .font(.caption).foregroundStyle(Theme.textMeta)

            Text("FREQUENCY").font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(Theme.textMeta)
            if escalation.isEmpty {
                Text("Uses the Repeat above (every \(repeatInterval) \(unitLabel)). Add phases to ramp it up over time — e.g. every 3 nights until a date, then every 2.")
                    .font(.caption2).foregroundStyle(Theme.textMeta)
            } else {
                ForEach($escalation) { $step in
                    let idx = escalation.firstIndex { $0.id == step.id } ?? 0
                    let isLast = idx == escalation.count - 1
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Phase \(idx + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                            Spacer()
                            Button { escalation.removeAll { $0.id == step.id } } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Theme.textMeta.opacity(0.6))
                            }.buttonStyle(.plain)
                        }
                        Stepper(value: $step.everyDays, in: 1...30) {
                            Text("Every \(step.everyDays) night\(step.everyDays == 1 ? "" : "s")")
                                .font(.subheadline).foregroundStyle(Theme.textMain)
                        }.tint(Theme.accent)
                        if isLast {
                            Text("…then stays at this frequency").font(.caption2).foregroundStyle(Theme.textMeta)
                        } else {
                            HStack(spacing: 6) {
                                Text("until").font(.caption).foregroundStyle(Theme.textMeta)
                                DatePicker("", selection: Binding(
                                    get: { parseDate(step.until) ?? (Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()) },
                                    set: { step.until = iso(Calendar.current.startOfDay(for: $0)) }
                                ), displayedComponents: .date).labelsHidden().tint(Theme.accent)
                            }
                        }
                    }
                    divider
                }
            }
            Button {
                // The previous final phase now needs an end date; the new phase is the open one.
                if !escalation.isEmpty, escalation[escalation.count - 1].until == nil {
                    escalation[escalation.count - 1].until = iso(Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date())
                }
                escalation.append(EscalationStep(everyDays: max(1, (escalation.last?.everyDays ?? 3) - 1), until: nil))
            } label: {
                Label("Add a later phase", systemImage: "plus.circle").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }

            divider
            Toggle(isOn: $askToReview.animation(Theme.spring)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask me to review the frequency").font(.subheadline).foregroundStyle(Theme.textMain)
                    Text("Don't know when to change it? Nudge checks in (~every 2 weeks) to step it up or down based on how your skin's reacting.")
                        .font(.caption2).foregroundStyle(Theme.textMeta)
                }
            }.tint(Theme.accent)
        }
        .padding(.vertical, 8)
    }

    // Multiple, customisable early reminders (offsets in minutes before due).
    private let earlyPresets: [(String, Int)] = [
        ("5 min", 5), ("15 min", 15), ("30 min", 30), ("1 hour", 60), ("2 hours", 120),
        ("1 day", 1440), ("2 days", 2880), ("1 week", 10080), ("2 weeks", 20160), ("1 month", 43200)
    ]
    private func earlyLabel(_ m: Int) -> String {
        if m % 43200 == 0 { let n = m/43200; return "\(n) month\(n == 1 ? "" : "s")" }
        if m % 10080 == 0 { let n = m/10080; return "\(n) week\(n == 1 ? "" : "s")" }
        if m % 1440 == 0  { let n = m/1440;  return "\(n) day\(n == 1 ? "" : "s")" }
        if m % 60 == 0    { let n = m/60;    return "\(n) hour\(n == 1 ? "" : "s")" }
        return "\(m) min"
    }
    private func addEarly(_ m: Int) {
        guard m > 0, !earlyAlerts.contains(m) else { return }
        withAnimation(Theme.spring) { earlyAlerts.append(m); earlyAlerts.sort(by: >) }
    }

    @ViewBuilder private var earlyAlertsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(earlyAlerts, id: \.self) { m in
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge").foregroundStyle(Theme.accent).frame(width: 22)
                    Text("\(earlyLabel(m)) before").foregroundStyle(Theme.textMain)
                    Spacer()
                    Button { withAnimation(Theme.spring) { earlyAlerts.removeAll { $0 == m } } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Theme.textMeta.opacity(0.6))
                    }.buttonStyle(.plain)
                }
            }
            Menu {
                ForEach(earlyPresets, id: \.1) { p in Button("\(p.0) before") { addEarly(p.1) } }
                Button("Custom…") { withAnimation(Theme.spring) { showCustomEarly = true } }
            } label: {
                Label(earlyAlerts.isEmpty ? "Add early reminder" : "Add another",
                      systemImage: "plus.circle").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            if showCustomEarly {
                HStack(spacing: 8) {
                    Stepper(value: $customEarlyVal, in: 1...99) {
                        Text("\(customEarlyVal)").foregroundStyle(Theme.textMain)
                    }.tint(Theme.accent).fixedSize()
                    Picker("", selection: $customEarlyUnit) {
                        Text("min").tag(1); Text("hours").tag(60); Text("days").tag(1440)
                        Text("weeks").tag(10080); Text("months").tag(43200)
                    }.pickerStyle(.menu).tint(Theme.accent)
                    Spacer()
                    Button("Add") {
                        addEarly(customEarlyVal * customEarlyUnit)
                        withAnimation(Theme.spring) { showCustomEarly = false }
                    }.font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // Apple-Reminders-style row: icon · title · blue value subtitle · toggle.
    // Tapping the label area runs `onTap` (used to expand/collapse the inline picker).
    private func schedRow(_ icon: String, _ title: String, subtitle: String?,
                          isOn: Binding<Bool>, onTap: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Button { onTap?() } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).foregroundStyle(Theme.textMain)
                        if let s = subtitle {
                            Text(s).font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 8)
    }

    private func relativeDateText(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        let f = DateFormatter()
        f.dateFormat = (days > 1 && days < 7) ? "EEEE" : "EEE d MMM"
        return f.string(from: d)
    }
    private func timeText(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: d)
    }

    private let timePresets: [(label: String, hour: Int, min: Int)] = [
        ("Morning", 9, 0), ("Midday", 12, 0), ("Afternoon", 15, 0), ("Evening", 18, 0), ("Night", 21, 0)
    ]

    private var timePresetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { applyRecommended() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                        Text("Recommended").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                ForEach(timePresets, id: \.label) { p in
                    let on = isPreset(p.hour, p.min)
                    Button { applyPreset(p.hour, p.min) } label: {
                        Text(p.label).font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : Theme.accent)
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14)), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 6)
    }

    private func isPreset(_ h: Int, _ m: Int) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: due)
        return c.hour == h && c.minute == m
    }

    private func applyRecommended() {
        hasTime = true
        withAnimation(Theme.snappy) { due = store.recommendedTime(title: title, on: due, excluding: editing?.id) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func applyPreset(_ h: Int, _ m: Int) {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: due)
        c.hour = h; c.minute = m
        let desired = Calendar.current.date(from: c) ?? due
        hasTime = true
        withAnimation(Theme.snappy) { due = store.nextFreeSlot(desired, excluding: editing?.id) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Buy-keyword rule: a NEW reminder whose title contains "buy" goes to the Shopping
    /// list, due the next payday at 09:00 — this month's 15th (or the Friday before, if
    /// it's a weekend) if it hasn't passed, otherwise next month's.
    private func applyBuyRule() {
        guard editing == nil else { return }
        guard title.range(of: "\\bbuy\\b", options: [.regularExpression, .caseInsensitive]) != nil else { return }
        if store.lists.contains(where: { $0.id == "shopping" }) { listId = "shopping" }
        hasDue = true; hasTime = true
        due = Payday.next()
    }

    /// "Claude - …" reminders (the Ask-Claude ones) file into the Claude list.
    private func isClaudeTitle(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespaces).lowercased()
        return s.hasPrefix("claude -") || s.hasPrefix("claude-")
    }
    private func applyClaudeRule() {
        guard editing == nil, isClaudeTitle(title) else { return }
        if store.lists.contains(where: { $0.id == "claude" }) { listId = "claude" }
    }

    /// Save, but first warn if the chosen time lands on a calendar event.
    private func attemptSave() {
        if hasDue, hasTime, let clash = CalendarService.shared.conflictDescription(at: due) {
            conflictMsg = clash
            showConflictAlert = true
        } else {
            save()
        }
    }

    private func save() {
        for u in removedURLs { ImageStore.delete(u) }
        for n in newImages { ImageStore.save(n.data, for: reminderId) }
        addSubtask()   // commit any half-typed subtask still in the field
        applyBuyRule()
        applyClaudeRule()
        var rec: Recurrence? = nil
        if repeatFreq != "none" {
            rec = Recurrence(freq: repeatFreq, interval: repeatInterval,
                             until: hasUntil ? iso(Calendar.current.startOfDay(for: until)) : nil)
        }
        store.saveReminder(editing: editing, title: title, notes: notes,
                           hasDue: hasDue, due: due, hasTime: hasTime,
                           listId: listId, priority: priority,
                           recurrence: rec, tz: tz.isEmpty ? nil : tz,
                           url: url, location: location, lat: lat, lng: lng,
                           pinned: pinned, remindBefores: earlyAlerts, subtasks: subtasks,
                           routine: routine, escalation: escalation, reviewFrequency: askToReview,
                           urgent: urgent,
                           idForNew: editing == nil ? draftId : nil)
        if editing == nil, let p = ClaudeLink.prompt(from: title) {
            AppRouter.shared.pendingClaudePrompt = p
        }
        dismiss()
    }
}

// Full-screen image preview (tap to close).
struct ImagePreview: View {
    let image: UIImage
    var onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit()
            VStack {
                HStack {
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white, .white.opacity(0.3))
                    }.padding()
                }
                Spacer()
            }
        }
    }
}
