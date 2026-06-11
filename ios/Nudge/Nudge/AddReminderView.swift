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
    @State private var listId = "reminders"
    @State private var priority = "normal"
    @State private var pinned = false
    @State private var remindBefore = 0          // minutes before due; 0 = off
    @State private var subtasks: [Subtask] = []
    @State private var newSubtask = ""
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
                    // Title
                    TextField("What do you need to remember?", text: $title, axis: .vertical)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textMain)
                        .focused($titleFocused)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    // Schedule
                    section("When") {
                        toggleRow("Due date", systemImage: "calendar", isOn: $hasDue.animation(Theme.spring))
                        if hasDue {
                            divider
                            DatePicker(selection: $due, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]) {
                                rowLabel("Date", "clock")
                            }
                            .tint(Theme.accent).padding(.vertical, 6)
                            divider
                            datePresetRow
                            if hasTime {
                                divider
                                timePresetRow
                            }
                            divider
                            toggleRow("Include time", systemImage: "clock.badge", isOn: $hasTime.animation(Theme.spring))
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
                            if hasTime {
                                divider
                                menuRow("Early reminder", "bell.badge") {
                                    Picker("Early reminder", selection: $remindBefore) {
                                        Text("None").tag(0)
                                        Text("5 min before").tag(5)
                                        Text("15 min before").tag(15)
                                        Text("30 min before").tag(30)
                                        Text("1 hour before").tag(60)
                                        Text("1 day before").tag(1440)
                                    }.labelsHidden().tint(Theme.accent)
                                }
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
            .navigationTitle(editing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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
        if let rec = r.recurrence, rec.freq != "none" {
            repeatFreq = rec.freq
            repeatInterval = max(1, rec.interval ?? 1)
            if let u = parseDate(rec.until) { hasUntil = true; until = u }
        }
        url = r.url ?? ""
        location = r.location ?? ""
        lat = r.lat; lng = r.lng
        remindBefore = r.remindBefore ?? 0
        subtasks = r.subtasks ?? []
        existingURLs = ImageStore.urls(for: r.id)
    }

    private func addSubtask() {
        let t = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        subtasks.append(Subtask(id: "s" + String(UUID().uuidString.prefix(11)), title: t, done: false))
        newSubtask = ""
    }

    // Quick time-of-day shortcuts. Tapping sets that time on the chosen day, then
    // nudges to the next free 15-min slot so it won't clash with another reminder.
    // Quick-date shortcuts (Apple-Reminders style). Each keeps the current time-of-day
    // and just moves the day; the active one highlights.
    private var datePresetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                dateChip("Today", dayOffset(0))
                dateChip("Tomorrow", dayOffset(1))
                dateChip("This Weekend", upcomingWeekend())
                dateChip("Next Week", nextWeekStart())
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 6)
    }

    private func dateChip(_ label: String, _ date: Date) -> some View {
        let on = Calendar.current.isDate(due, inSameDayAs: date)
        return Button { applyDate(date) } label: {
            Text(label).font(.caption.weight(.semibold))
                .foregroundStyle(on ? .white : Theme.accent)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14)), in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func applyDate(_ date: Date) {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: due)
        var c = cal.dateComponents([.year, .month, .day], from: date)
        c.hour = hasTime ? (t.hour ?? 9) : 0
        c.minute = hasTime ? (t.minute ?? 0) : 0
        withAnimation(Theme.snappy) { due = cal.date(from: c) ?? date }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func dayOffset(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
    private func upcomingWeekend() -> Date {   // upcoming Saturday (or today if it's the weekend)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = cal.component(.weekday, from: today)   // 1=Sun … 7=Sat
        if wd == 1 { return today }                      // Sunday → this weekend is today
        return cal.date(byAdding: .day, value: (7 - wd) % 7, to: today) ?? today
    }
    private func nextWeekStart() -> Date {     // next Monday
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = cal.component(.weekday, from: today)
        var add = (2 - wd + 7) % 7
        if add == 0 { add = 7 }
        return cal.date(byAdding: .day, value: add, to: today) ?? today
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

    /// Buy-keyword rule: a NEW reminder whose title contains "buy" goes to the
    /// Shopping list at a fixed 9 AM — bumped to the next free slot if 9 AM is
    /// already taken (so multiple buy reminders don't pile onto the same minute).
    private func applyBuyRule() {
        guard editing == nil else { return }
        guard title.range(of: "\\bbuy\\b", options: [.regularExpression, .caseInsensitive]) != nil else { return }
        if store.lists.contains(where: { $0.id == "shopping" }) { listId = "shopping" }
        let cal = Calendar.current
        let baseDay = hasDue ? due : Date()
        hasDue = true; hasTime = true
        var c = cal.dateComponents([.year, .month, .day], from: baseDay)
        c.hour = 9; c.minute = 0
        let nine = cal.date(from: c) ?? due
        due = store.nextFreeSlot(nine, excluding: nil)
    }

    private func save() {
        for u in removedURLs { ImageStore.delete(u) }
        for n in newImages { ImageStore.save(n.data, for: reminderId) }
        addSubtask()   // commit any half-typed subtask still in the field
        applyBuyRule()
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
                           pinned: pinned, remindBefore: remindBefore, subtasks: subtasks,
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
