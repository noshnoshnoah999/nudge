// FolderViews.swift — Nudge (iOS)
// User-made folders (2026-10-07).
//
// What Noah asked for:
//   • Create a folder with a NAME and an ICON (SF Symbol, no colour). Rename / delete.
//   • On every reminder page (Today, Overdue, Upcoming, Smart Collections) reminders are
//     shown under collapsible folder headings; reminders in no folder sit at the BOTTOM.
//   • A reminder can be in SEVERAL folders and then shows under each. Adding one that's
//     already in a folder to another folder shows a warning but still lets you.
//   • Add via multi-select, via each reminder's long-press menu, and via the Add screen.
//   • Deleting a folder only removes the label — no reminder is deleted or moved.
//   • Hold-and-drag to reorder folders; the order is the same on every page.
//   • The widget is unchanged (it still lists reminders, not folders).
//
// Storage + sync: see "Folders" in NudgeStore.swift.

import SwiftUI

// MARK: - Icon choices

enum FolderIcons {
    /// Curated SF Symbols. Plain line icons only, so they read the same in every theme.
    static let all: [String] = [
        "folder", "tray", "archivebox", "doc.text", "book", "graduationcap", "pencil",
        "briefcase", "laptopcomputer", "lightbulb", "calendar", "clock", "bell", "flag",
        "star", "heart", "house", "cart", "bag", "gift", "creditcard", "yensign.circle",
        "sterlingsign.circle", "car", "tram", "airplane", "globe", "fork.knife",
        "cup.and.saucer", "leaf", "sun.max", "moon", "dumbbell", "figure.run", "pills",
        "cross.case", "person", "person.2", "pawprint", "gamecontroller", "music.note",
        "film", "camera", "paintbrush", "wrench.and.screwdriver", "iphone"
    ]
}

// MARK: - Create / edit a folder

struct FolderEditorSheet: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    /// nil = create a new folder.
    let editing: Folder?
    /// Called with the folder after it's saved (used to file reminders into a new folder).
    var onSaved: (Folder) -> Void = { _ in }

    @State private var name = ""
    @State private var icon = "folder"
    @FocusState private var nameFocused: Bool

    private let grid = [GridItem(.adaptive(minimum: 46), spacing: 10)]
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous))
                        TextField("Folder name", text: $name)
                            .font(.title3.weight(.semibold))
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius(16), style: .continuous))

                    Text("ICON").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                    LazyVGrid(columns: grid, spacing: 10) {
                        ForEach(FolderIcons.all, id: \.self) { sym in
                            Button { icon = sym } label: {
                                Image(systemName: sym)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(icon == sym ? Theme.onAccent : Theme.textMain)
                                    .frame(width: 46, height: 46)
                                    .background(icon == sym ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                                                in: RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sym)
                        }
                    }
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(editing == nil ? "New Folder" : "Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).bold().disabled(trimmed.isEmpty)
                }
            }
            .onAppear {
                if let f = editing { name = f.name; icon = f.icon }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nameFocused = true }
            }
        }
        .tint(Theme.controlTint)
        .presentationBackground(Theme.bg)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        if let f = editing {
            store.updateFolder(f.id, name: trimmed, icon: icon)
            onSaved(Folder(id: f.id, name: trimmed, icon: icon))
        } else {
            onSaved(store.createFolder(name: trimmed, icon: icon))
        }
        dismiss()
    }
}

// MARK: - File one or many reminders into folders

/// Used from a reminder's long-press menu (one id) and from multi-select (many ids).
/// Tapping a folder adds every reminder to it; tapping a folder they're ALL already in
/// removes them. Adding a reminder that's already in another folder asks first — but
/// "Add anyway" always goes through.
struct FolderPickerSheet: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let reminderIds: [String]

    @State private var showNew = false
    @State private var pendingAdd: Folder?
    @State private var pendingAlreadyCount = 0

    private var targets: [Reminder] { store.reminders.filter { reminderIds.contains($0.id) } }
    private var validIds: Set<String> { Set(store.folders.map(\.id)) }

    var body: some View {
        NavigationStack {
            List {
                if store.folders.isEmpty {
                    Text("No folders yet. Make one below.")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)
                }
                ForEach(store.folders) { f in
                    let inCount = targets.filter { $0.folderIds?.contains(f.id) == true }.count
                    Button { tap(f, inCount: inCount) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: f.icon).frame(width: 26).foregroundStyle(Theme.accent)
                            Text(f.name).foregroundStyle(Theme.textMain)
                            Spacer()
                            if inCount == targets.count && inCount > 0 {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                            } else if inCount > 0 {
                                Image(systemName: "minus").font(.body.weight(.semibold)).foregroundStyle(Theme.textMeta)
                            }
                        }
                    }
                }
                Button { showNew = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus").foregroundStyle(Theme.accent)
                }
            }
            .navigationTitle(reminderIds.count == 1 ? "Folders" : "Add \(reminderIds.count) to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showNew) {
                FolderEditorSheet(editing: nil) { f in tap(f, inCount: 0) }.environmentObject(store)
            }
            .alert("Already in another folder", isPresented: Binding(
                get: { pendingAdd != nil }, set: { if !$0 { pendingAdd = nil } })) {
                Button("Add anyway") {
                    if let f = pendingAdd { store.addReminders(reminderIds, toFolder: f.id) }
                    pendingAdd = nil
                }
                Button("Cancel", role: .cancel) { pendingAdd = nil }
            } message: {
                Text(pendingAlreadyCount == 1 && reminderIds.count == 1
                     ? "This reminder is already in a folder. It will show under both."
                     : "\(pendingAlreadyCount) of these reminders are already in another folder. They will show under each folder they're in.")
            }
        }
        .tint(Theme.controlTint)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }

    private func tap(_ f: Folder, inCount: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        if inCount == targets.count && inCount > 0 {
            store.removeReminders(reminderIds, fromFolder: f.id)
            return
        }
        // Warn when any reminder being added is already filed in a DIFFERENT folder.
        let already = targets.filter { r in
            r.folderIds?.contains(f.id) != true &&
            (r.folderIds ?? []).contains(where: { validIds.contains($0) && $0 != f.id })
        }.count
        if already > 0 {
            pendingAlreadyCount = already
            pendingAdd = f
        } else {
            store.addReminders(reminderIds, toFolder: f.id)
        }
    }
}

// MARK: - Folder membership for the Add / Edit screen

/// The reminder may not exist yet on the Add screen, so this edits a local list of ids that
/// AddReminderView writes with store.setFolderIds after saving.
struct FolderMembershipMenu: View {
    @EnvironmentObject var store: NudgeStore
    @Binding var folderIds: [String]
    @State private var pendingAdd: Folder?
    @State private var showNew = false

    private var current: [Folder] { store.folders.filter { folderIds.contains($0.id) } }

    var body: some View {
        Menu {
            ForEach(store.folders) { f in
                Button {
                    if folderIds.contains(f.id) {
                        folderIds.removeAll { $0 == f.id }
                    } else if !current.isEmpty {
                        pendingAdd = f   // already in a folder → warn, but allow
                    } else {
                        folderIds.append(f.id)
                    }
                } label: {
                    if folderIds.contains(f.id) { Label(f.name, systemImage: "checkmark") }
                    else { Label(f.name, systemImage: f.icon) }
                }
            }
            Divider()
            Button { showNew = true } label: { Label("New Folder…", systemImage: "folder.badge.plus") }
        } label: {
            Text(current.isEmpty ? "None" : current.map(\.name).joined(separator: ", "))
                .lineLimit(1)
                .foregroundStyle(current.isEmpty ? Theme.textMeta : Theme.accent)
        }
        .sheet(isPresented: $showNew) {
            FolderEditorSheet(editing: nil) { f in
                if current.isEmpty { folderIds.append(f.id) } else { pendingAdd = f }
            }
            .environmentObject(store)
        }
        .alert("Already in a folder", isPresented: Binding(
            get: { pendingAdd != nil }, set: { if !$0 { pendingAdd = nil } })) {
            Button("Add anyway") {
                if let f = pendingAdd, !folderIds.contains(f.id) { folderIds.append(f.id) }
                pendingAdd = nil
            }
            Button("Cancel", role: .cancel) { pendingAdd = nil }
        } message: {
            Text("This reminder is already in \(current.map(\.name).joined(separator: ", ")). It will show under both.")
        }
    }
}

// MARK: - Manage folders (Lists tab)

struct FoldersManagerView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingFolder: Folder?
    @State private var showNew = false
    @State private var confirmDelete: Folder?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.folders) { f in
                        Button { editingFolder = f } label: {
                            HStack(spacing: 12) {
                                Image(systemName: f.icon).frame(width: 26).foregroundStyle(Theme.accent)
                                Text(f.name).foregroundStyle(Theme.textMain)
                                Spacer()
                                Text("\(store.open().filter { $0.folderIds?.contains(f.id) == true }.count)")
                                    .font(.subheadline).foregroundStyle(Theme.textMeta)
                            }
                        }
                    }
                    .onMove { store.reorderFolders(fromOffsets: $0, toOffset: $1) }
                    // Edit mode is always on (for the handles), so delete is the red minus
                    // button, which asks for confirmation before anything changes.
                    .onDelete { idx in
                        if let i = idx.first, store.folders.indices.contains(i) { confirmDelete = store.folders[i] }
                    }
                } footer: {
                    Text("Drag the handles to reorder — the order is the same on every page. Deleting a folder never deletes its reminders.")
                }
                Button { showNew = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus").foregroundStyle(Theme.accent)
                }
            }
            .environment(\.editMode, .constant(.active))   // always show reorder handles
            .navigationTitle("Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingFolder) { f in FolderEditorSheet(editing: f).environmentObject(store) }
            .sheet(isPresented: $showNew) { FolderEditorSheet(editing: nil).environmentObject(store) }
            .alert("Delete \"\(confirmDelete?.name ?? "")\"?", isPresented: Binding(
                get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("Delete Folder", role: .destructive) {
                    if let f = confirmDelete { withAnimation { store.deleteFolder(f.id) } }
                    confirmDelete = nil
                }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            } message: {
                Text("Only the folder is removed. Its reminders stay exactly where they are.")
            }
        }
        .tint(Theme.controlTint)
        .presentationBackground(Theme.bg)
    }
}

// MARK: - One folder's reminders (tap a folder on the Lists tab)

struct FolderContentsView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let folder: Folder
    @State private var editingReminder: Reminder?
    @State private var showEdit = false

    private var items: [Reminder] {
        store.open().filter { $0.folderIds?.contains(folder.id) == true }
            .sorted { (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture) }
    }
    /// Re-read so a rename shows straight away.
    private var live: Folder { store.folders.first { $0.id == folder.id } ?? folder }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if items.isEmpty {
                        Text("Nothing in this folder. Long-press a reminder → Folders… to add one.")
                            .font(.subheadline).foregroundStyle(Theme.textMeta)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(items) { r in
                            ReminderCardView(reminder: r) { editingReminder = r }
                        }
                    }
                }
                .padding(16)
                .animation(Theme.spring, value: store.reminders)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(live.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Edit") { showEdit = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingReminder) { r in AddReminderView(editing: r).environmentObject(store) }
            .sheet(isPresented: $showEdit) { FolderEditorSheet(editing: live).environmentObject(store) }
        }
        .tint(Theme.controlTint)
        .presentationBackground(Theme.bg)
    }
}

// MARK: - Folder sections on a reminder page

/// Splits a page's reminders into collapsible folder sections (in the user's folder order),
/// with reminders in no folder at the bottom. If none of `items` is in a folder, it renders
/// `rows(items)` exactly as before — pages with no folders look unchanged.
///
/// `rows` renders a flat run of reminders the way the page always has (AI group cards,
/// select mode, etc.), so folders sit ON TOP of existing behaviour rather than replacing it.
/// Each section is its own container, so a reminder in two folders can appear in both
/// without SwiftUI identity clashes.
///
/// Folder headers can be long-pressed and dragged onto another folder header to reorder.
struct FolderedSections<Rows: View>: View {
    @EnvironmentObject var store: NudgeStore
    @EnvironmentObject var settings: AppSettings
    let items: [Reminder]
    /// Page key for remembering which folders are collapsed (per page, on this device).
    let scope: String
    @ViewBuilder let rows: ([Reminder]) -> Rows

    @AppStorage("collapsedFolderSections") private var collapsedRaw = ""
    @State private var dropTarget: String?

    private static var dragPrefix: String { "nudge-folder:" }
    private var collapsedKeys: Set<String> { Set(collapsedRaw.split(separator: "\n").map(String.init)) }
    private func key(_ f: Folder) -> String { "\(scope)|\(f.id)" }

    var body: some View {
        let present = store.folders.filter { f in items.contains { $0.folderIds?.contains(f.id) == true } }
        if present.isEmpty {
            rows(items)
        } else {
            ForEach(present) { f in
                let members = items.filter { $0.folderIds?.contains(f.id) == true }
                let isCollapsed = collapsedKeys.contains(key(f))
                VStack(alignment: .leading, spacing: Theme.minimal ? 0 : (settings.compact ? 8 : 10)) {
                    header(f, count: members.count, isCollapsed: isCollapsed)
                    if !isCollapsed { rows(members) }
                }
                .padding(.top, 4)
            }
            let valid = Set(store.folders.map(\.id))
            let unfiled = items.filter { !($0.folderIds ?? []).contains(where: valid.contains) }
            if !unfiled.isEmpty {
                VStack(alignment: .leading, spacing: Theme.minimal ? 0 : (settings.compact ? 8 : 10)) {
                    Text("NOT IN A FOLDER")
                        .font(.caption.weight(.semibold))
                        .tracking(Theme.minimal ? 1 : 0.8)
                        .foregroundStyle(Theme.textMeta)
                        .padding(.leading, Theme.minimal ? 0 : 2)
                        .padding(.bottom, Theme.minimal ? 8 : 0)
                        .padding(.top, 8)
                    rows(unfiled)
                }
            }
        }
    }

    private func toggle(_ f: Folder) {
        var s = collapsedKeys
        if s.contains(key(f)) { s.remove(key(f)) } else { s.insert(key(f)) }
        collapsedRaw = s.sorted().joined(separator: "\n")
    }

    private func header(_ f: Folder, count: Int, isCollapsed: Bool) -> some View {
        Button {
            withAnimation(Theme.spring) { toggle(f) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: f.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                Text(f.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textMain)
                    .lineLimit(1)
                if !Theme.minimal {
                    Text("\(count)").font(.caption2.weight(.bold))
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.textMeta)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Theme.surfaceAlt, in: Capsule())
                } else {
                    Text("\(count)").font(.subheadline).foregroundStyle(Theme.textMeta)
                }
                Spacer()
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textMeta.opacity(Theme.minimal ? 0.5 : 1))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .padding(.bottom, Theme.minimal ? 4 : 0)
            .background(dropTarget == f.id ? Theme.accentSoft : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.radius(10), style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Hold and drag a header onto another header to reorder folders everywhere.
        .draggable(Self.dragPrefix + f.id) {
            Label(f.name, systemImage: f.icon)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .dropDestination(for: String.self) { payload, _ in
            guard let s = payload.first, s.hasPrefix(Self.dragPrefix) else { return false }
            let id = String(s.dropFirst(Self.dragPrefix.count))
            withAnimation(Theme.spring) { store.moveFolder(id, onto: f.id) }
            return true
        } isTargeted: { on in dropTarget = on ? f.id : (dropTarget == f.id ? nil : dropTarget) }
    }
}
