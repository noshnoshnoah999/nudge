// RemindersSync.swift — Nudge (iOS)
// Two-way sync between Nudge and Apple Reminders via EventKit (Task #22).
//
// Model: Nudge mirrors a single dedicated "Nudge" list in Apple Reminders. Your
// other Apple lists are never touched. Anything captured in either place (Siri,
// Control Center, Watch → the Nudge list; or the Nudge app) flows to the other.
//
// Reconciliation is a three-way merge against a locally-stored snapshot of the
// last-synced state, so we know *which* side actually changed rather than just
// that the two differ. True simultaneous edits fall back to most-recently-edited
// wins (Nudge's `updatedAt` vs Apple's `lastModifiedDate`).
//
// Scope of this slice: title, due date (+time), notes, and completion sync
// continuously both ways; creations and deletions propagate both ways. Priority
// and list are seeded on creation only. Recurrence / subtasks / tags are NOT
// pushed to EventKit (Nudge keeps its own richer model for those).

import Foundation
import EventKit
import SwiftUI
import Combine

/// A set of identical reminders (same title + due-to-minute) found during cleanup:
/// one to keep, the rest to remove. Shown in the confirm-first review sheet.
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let keep: Reminder
    let remove: [Reminder]
}

@MainActor
final class RemindersSync: ObservableObject {
    enum Status: Equatable {
        case idle, syncing, ok(String), denied, error(String)
    }

    @Published var status: Status = .idle
    @Published private(set) var lastSync: Date?
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Keys.enabled) }
    }

    private let ek = EKEventStore()
    private weak var nudge: NudgeStore?
    private var syncing = false
    private var editSyncTask: Task<Void, Never>?

    private enum Keys {
        static let enabled = "appleSyncEnabled"
        static let calendarId = "nudgeCalendarId"
        static let lastSync = "appleSyncLastDate"
    }

    init() {
        enabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        if let t = UserDefaults.standard.object(forKey: Keys.lastSync) as? Date { lastSync = t }
    }

    func attach(_ store: NudgeStore) {
        nudge = store
        NotificationCenter.default.addObserver(forName: .nudgeDataChanged, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.scheduleEditSync() }
        }
    }

    /// Debounced push triggered by local edits (complete / edit / delete / add).
    private func scheduleEditSync() {
        guard enabled, !syncing else { return }
        editSyncTask?.cancel()
        editSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            await self?.syncNow()
        }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    // MARK: - Public entry points

    /// Turn sync on: request access, then run an initial sync.
    func enable() async {
        let granted = hasAccess ? true : (await requestAccess())
        guard granted else { enabled = false; status = .denied; return }
        enabled = true
        await syncNow()
    }

    func disable() {
        enabled = false
        status = .idle
    }

    /// Run a full reconciliation. Safe to call repeatedly; no-ops while in flight.
    func syncNow() async {
        guard enabled, !syncing, let nudge else { return }
        syncing = true
        defer { syncing = false }
        status = .syncing

        let granted = hasAccess ? true : (await requestAccess())
        guard granted else { status = .denied; enabled = false; return }

        do {
            let (cal, createdNew) = try ensureCalendar()
            try await reconcile(calendar: cal, nudge: nudge, freshCalendar: createdNew)
            let now = Date()
            lastSync = now
            UserDefaults.standard.set(now, forKey: Keys.lastSync)
            status = .ok(summary)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private var summary: String {
        guard let n = nudge else { return "Synced" }
        let count = links.count
        return "\(count) item\(count == 1 ? "" : "s") · \(n.syncState == "Offline" ? "cloud offline" : "synced")"
    }

    // MARK: - Duplicate cleanup (confirm-first)

    private func dedupKey(_ r: Reminder) -> String {
        r.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + canonDue(r)
    }

    /// Find duplicate reminders WITHOUT changing anything — for the review-before-remove
    /// UI. Groups live reminders by title + due-to-minute; each group keeps an UNFINISHED
    /// copy where possible (then the oldest) and lists the rest as removable.
    func planDuplicates() -> [DuplicateGroup] {
        guard let nudge else { return [] }
        var groups: [String: [Reminder]] = [:]
        for r in nudge.reminders where !(r.dismissed ?? false) {
            groups[dedupKey(r), default: []].append(r)
        }
        var out: [DuplicateGroup] = []
        for (_, rs) in groups where rs.count > 1 {
            let sorted = rs.sorted { a, b in
                let ac = a.completed ?? false, bc = b.completed ?? false
                if ac != bc { return !ac }   // keep an incomplete copy if any exists
                return (parseDate(a.createdAt) ?? .distantPast) < (parseDate(b.createdAt) ?? .distantPast)
            }
            out.append(DuplicateGroup(keep: sorted[0], remove: Array(sorted.dropFirst())))
        }
        return out.sorted { displayTitle($0.keep).lowercased() < displayTitle($1.keep).lowercased() }
    }

    /// Remove exactly the duplicates the user confirmed. Deletes only from Nudge — the
    /// next sync removes each one's linked Apple twin (and the reconcile re-link fix stops
    /// re-import), so we never do a blind Apple-side scan that could delete the wrong item.
    @discardableResult
    func applyDuplicates(_ groups: [DuplicateGroup]) -> Int {
        guard let nudge else { return 0 }
        let removeIds = Set(groups.flatMap { $0.remove.map(\.id) })
        guard !removeIds.isEmpty else { return 0 }
        nudge.reminders.removeAll { removeIds.contains($0.id) }
        nudge.persist()   // reconcile mirrors the deletions to Apple Reminders
        return removeIds.count
    }

    // MARK: - Access

    private func requestAccess() async -> Bool {
        (try? await ek.requestFullAccessToReminders()) ?? false
    }

    // MARK: - Dedicated calendar

    enum SyncError: LocalizedError {
        case noSource
        var errorDescription: String? {
            switch self {
            case .noSource: return "No Reminders account available to create the Nudge list."
            }
        }
    }

    /// Returns the dedicated Nudge calendar and whether it was created fresh this
    /// call (i.e. there was no usable existing list). A fresh calendar means any
    /// saved links are stale and must be discarded, not treated as Apple-side
    /// deletions — otherwise deleting the list in Apple would wipe Nudge.
    private func ensureCalendar() throws -> (EKCalendar, Bool) {
        if let id = UserDefaults.standard.string(forKey: Keys.calendarId),
           let cal = ek.calendar(withIdentifier: id), cal.allowsContentModifications {
            return (cal, false)
        }
        if let existing = ek.calendars(for: .reminder).first(where: { $0.title == "Nudge" }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: Keys.calendarId)
            return (existing, false)
        }
        let cal = EKCalendar(for: .reminder, eventStore: ek)
        cal.title = "Nudge"
        guard let src = bestSource() else { throw SyncError.noSource }
        cal.source = src
        try ek.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: Keys.calendarId)
        return (cal, true)
    }

    private func bestSource() -> EKSource? {
        if let s = ek.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) { return s }
        if let s = ek.defaultCalendarForNewReminders()?.source { return s }
        if let s = ek.sources.first(where: { $0.sourceType == .local }) { return s }
        return ek.sources.first
    }

    private func fetchReminders(in cal: EKCalendar) async -> [EKReminder] {
        let pred = ek.predicateForReminders(in: [cal])
        return await withCheckedContinuation { cont in
            ek.fetchReminders(matching: pred) { items in
                cont.resume(returning: items ?? [])
            }
        }
    }

    // MARK: - Link store (local, never written to the shared cloud blob)

    struct Snapshot: Codable, Equatable {
        var title: String
        var dueCanon: String   // "" = no due date
        var notes: String      // "" = none
        var completed: Bool
        var url: String        // "" = none  (recurrence is Nudge-owned, not tracked here)

        init(title: String, dueCanon: String, notes: String, completed: Bool, url: String = "") {
            self.title = title; self.dueCanon = dueCanon; self.notes = notes
            self.completed = completed; self.url = url
        }
        // Custom decode so link files written before `url` existed still load
        // (missing key → ""). Without this, decoding would throw, links would
        // reset, and every reminder would re-import as a duplicate.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            dueCanon = try c.decode(String.self, forKey: .dueCanon)
            notes = try c.decode(String.self, forKey: .notes)
            completed = try c.decode(Bool.self, forKey: .completed)
            url = (try? c.decode(String.self, forKey: .url)) ?? ""
        }
    }
    struct Link: Codable {
        var nudgeId: String
        var ekExternalId: String
        var snap: Snapshot
    }

    private var links: [String: Link] = [:]   // keyed by nudgeId

    private var linksURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nudge_sync_links.json")
    }
    private func loadLinks() {
        guard let d = try? Data(contentsOf: linksURL),
              let arr = try? JSONDecoder().decode([Link].self, from: d) else { links = [:]; return }
        links = Dictionary(uniqueKeysWithValues: arr.map { ($0.nudgeId, $0) })
    }
    private func saveLinks() {
        let arr = Array(links.values)
        if let d = try? JSONEncoder().encode(arr) { try? d.write(to: linksURL) }
    }

    // MARK: - Reconciliation (three-way merge)

    private func reconcile(calendar cal: EKCalendar, nudge: NudgeStore, freshCalendar: Bool) async throws {
        loadLinks()
        nudge.backupSnapshot("sync")   // snapshot before any merge can mutate local data

        // A brand-new calendar invalidates every saved link. Drop them so the
        // reconcile re-pushes Nudge's items instead of reading the missing Apple
        // counterparts as deletions.
        if freshCalendar { links = [:] }
        let eks = await fetchReminders(in: cal)
        var ekByExt: [String: EKReminder] = [:]
        for e in eks { ekByExt[e.calendarItemExternalIdentifier] = e }

        // "Known" = what existed at the start of this sync.
        let knownEKIds = Set(links.values.map { $0.ekExternalId })

        var nudgeChanged = false
        var commitEK = false
        var nudgeIdsToDelete: Set<String> = []

        func liveIndex(_ id: String) -> Int? { nudge.reminders.firstIndex { $0.id == id } }
        func isLive(_ r: Reminder) -> Bool { !(r.dismissed ?? false) }
        // Content key used to re-link items whose external id link is missing —
        // prevents duplicates (lost link / second device) and disappear→reappear
        // churn (iCloud changing an item's external id).
        func fp(_ s: Snapshot) -> String {
            s.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + s.dueCanon
        }

        // Apple items that currently carry NO link, indexed by fingerprint (title+due)
        // and, as a fallback, by title alone — so a reminder whose DUE was edited in
        // Nudge can still re-link to its Apple twin instead of being deleted and then
        // re-imported from Apple's stale copy.
        func titleKey(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var unlinkedEKByFP: [String: EKReminder] = [:]
        var unlinkedEKByTitle: [String: EKReminder] = [:]
        for e in eks where !knownEKIds.contains(e.calendarItemExternalIdentifier) {
            let f = fp(snapshot(e))
            if unlinkedEKByFP[f] == nil { unlinkedEKByFP[f] = e }
            let t = titleKey(e.title ?? "")
            if unlinkedEKByTitle[t] == nil { unlinkedEKByTitle[t] = e }
        }
        var consumedEK = Set<String>()
        func takeUnlinkedEK(_ f: String) -> EKReminder? {
            guard let e = unlinkedEKByFP[f],
                  !consumedEK.contains(e.calendarItemExternalIdentifier) else { return nil }
            consumedEK.insert(e.calendarItemExternalIdentifier)
            return e
        }
        func takeUnlinkedEKByTitle(_ t: String) -> EKReminder? {
            guard let e = unlinkedEKByTitle[t],
                  !consumedEK.contains(e.calendarItemExternalIdentifier) else { return nil }
            consumedEK.insert(e.calendarItemExternalIdentifier)
            return e
        }

        // 1) Process every existing link.
        for (nid, link) in links {
            let nIdx = liveIndex(nid).flatMap { isLive(nudge.reminders[$0]) ? $0 : nil }
            let e = ekByExt[link.ekExternalId]

            switch (nIdx, e) {
            case let (idx?, ek?):
                // Backfill repeat/link that older syncs never imported (fill-only;
                // ignored by the snapshot below, so it never triggers churn).
                if backfillFromApple(&nudge.reminders[idx], from: ek) { nudgeChanged = true }
                let cur = nudge.reminders[idx]
                let nSnap = snapshot(cur)
                let eSnap = snapshot(ek)
                let nChanged = nSnap != link.snap
                let eChanged = eSnap != link.snap

                if nChanged || eChanged {
                    let nTime = parseDate(cur.updatedAt) ?? .distantPast
                    let eTime = ek.lastModifiedDate ?? .distantPast
                    // Apple overwrites Nudge ONLY when it genuinely changed and is
                    // strictly newer than Nudge's last edit. Otherwise Nudge wins and
                    // re-pushes — a stale Apple/iCloud copy can never silently revert
                    // a reminder the user just edited in Nudge.
                    if eChanged && eTime > nTime {
                        var rr = cur; writeToNudge(&rr, from: ek)
                        // A routine ticked in Apple Reminders would otherwise be marked
                        // completed and stop forever — roll it forward instead. Next sync
                        // pass writes the advanced/open state back to Apple.
                        if (rr.routine ?? false) && (rr.completed ?? false) {
                            nudge.advanceRoutine(&rr, night: parseDate(cur.dueDate) ?? Date())
                        }
                        nudge.reminders[idx] = rr; nudgeChanged = true
                        links[nid]?.snap = snapshot(rr)
                    } else {
                        writeToEK(ek, from: cur); try ek_save(ek); commitEK = true
                        links[nid]?.snap = nSnap
                    }
                }
                // neither changed → nothing to do

            case (nil, let ek?):
                // Gone from Nudge (deleted or dismissed) → remove from Apple.
                try ek_remove(ek); commitEK = true
                links[nid] = nil

            case let (idx?, nil):
                // Stored Apple item not found by its id. It may just have had its
                // external id change (iCloud) — re-link by content before assuming
                // a deletion, so the reminder doesn't vanish then reappear.
                if let e2 = takeUnlinkedEK(fp(snapshot(nudge.reminders[idx])))
                            ?? takeUnlinkedEKByTitle(titleKey(nudge.reminders[idx].title)) {
                    links[nid]?.ekExternalId = e2.calendarItemExternalIdentifier
                } else {
                    nudgeIdsToDelete.insert(nudge.reminders[idx].id)
                    links[nid] = nil
                }

            case (nil, nil):
                links[nid] = nil
            }
        }

        if !nudgeIdsToDelete.isEmpty {
            nudge.reminders.removeAll { nudgeIdsToDelete.contains($0.id) }
            nudgeChanged = true
        }

        // 2) Unlinked Nudge item → re-link to a matching Apple item, else create.
        var pendingNew: [(String, EKReminder)] = []
        for r in nudge.reminders where isLive(r) && links[r.id] == nil {
            if let e = takeUnlinkedEK(fp(snapshot(r))) {
                writeToEK(e, from: r); try ek_save(e); commitEK = true
                links[r.id] = Link(nudgeId: r.id, ekExternalId: e.calendarItemExternalIdentifier, snap: snapshot(r))
            } else {
                let ekNew = EKReminder(eventStore: ek)
                ekNew.calendar = cal
                writeToEK(ekNew, from: r)
                ekNew.priority = ekPriority(r.priorityOrNormal)   // seed priority once, on creation
                try ek_save(ekNew); commitEK = true
                pendingNew.append((r.id, ekNew))
            }
        }

        // 3) Unlinked Apple item → re-link to a matching Nudge item, else import.
        var unlinkedNudgeByFP: [String: Int] = [:]
        for (i, r) in nudge.reminders.enumerated() where isLive(r) && links[r.id] == nil {
            let f = fp(snapshot(r))
            if unlinkedNudgeByFP[f] == nil { unlinkedNudgeByFP[f] = i }
        }
        // Every live Nudge reminder by fingerprint, LINKED OR NOT — so an Apple item whose
        // Nudge twin is already linked to a now-dead Apple id gets RE-LINKED, not imported
        // as a duplicate. (This was the cause of the Apple-sync duplicate reminders.)
        var liveNudgeIdxByFP: [String: Int] = [:]
        for (i, r) in nudge.reminders.enumerated() where isLive(r) {
            let f = fp(snapshot(r)); if liveNudgeIdxByFP[f] == nil { liveNudgeIdxByFP[f] = i }
        }
        for e in eks where !knownEKIds.contains(e.calendarItemExternalIdentifier)
                          && !consumedEK.contains(e.calendarItemExternalIdentifier) {
            let f = fp(snapshot(e))
            if let i = unlinkedNudgeByFP[f], links[nudge.reminders[i].id] == nil {
                let rid = nudge.reminders[i].id
                links[rid] = Link(nudgeId: rid, ekExternalId: e.calendarItemExternalIdentifier, snap: snapshot(e))
                unlinkedNudgeByFP[f] = nil
            } else if let i = liveNudgeIdxByFP[f] {
                // Same content already exists in Nudge. If that reminder's Apple link is
                // stale/missing, adopt THIS Apple item; otherwise `e` is an Apple-side
                // duplicate — skip it. Either way, never create a second Nudge copy.
                let rid = nudge.reminders[i].id
                if links[rid] == nil || ekByExt[links[rid]!.ekExternalId] == nil {
                    links[rid] = Link(nudgeId: rid, ekExternalId: e.calendarItemExternalIdentifier, snap: snapshot(e))
                }
            } else {
                let r = newNudgeReminder(from: e)
                nudge.reminders.insert(r, at: 0); nudgeChanged = true
                links[r.id] = Link(nudgeId: r.id, ekExternalId: e.calendarItemExternalIdentifier, snap: snapshot(e))
            }
        }

        // 4) Commit EventKit once, then record links for newly created items
        // (external identifier is only stable after commit).
        if commitEK { try ek.commit() }
        for (nid, ekNew) in pendingNew {
            if let i = nudge.reminders.firstIndex(where: { $0.id == nid }) {
                links[nid] = Link(nudgeId: nid,
                                  ekExternalId: ekNew.calendarItemExternalIdentifier,
                                  snap: snapshot(nudge.reminders[i]))
            }
        }

        saveLinks()
        if nudgeChanged { nudge.persist(notify: false) }
    }

    // EventKit save/remove with deferred commit (we commit once at the end).
    private func ek_save(_ r: EKReminder) throws { try ek.save(r, commit: false) }
    private func ek_remove(_ r: EKReminder) throws { try ek.remove(r, commit: false) }

    // MARK: - Field mapping

    private func snapshot(_ r: Reminder) -> Snapshot {
        Snapshot(title: r.title, dueCanon: canonDue(r), notes: r.notes ?? "",
                 completed: r.completed ?? false, url: r.url ?? "")
    }
    private func snapshot(_ e: EKReminder) -> Snapshot {
        Snapshot(title: e.title ?? "", dueCanon: canonDue(e), notes: e.notes ?? "",
                 completed: e.isCompleted, url: e.url?.absoluteString ?? "")
    }

    private func canonDue(_ r: Reminder) -> String {
        guard let d = parseDate(r.dueDate) else { return "" }
        return canon(d, hasTime: r.hasTime ?? false)
    }
    private func canonDue(_ e: EKReminder) -> String {
        guard let c = e.dueDateComponents, let d = Calendar.current.date(from: c) else { return "" }
        return canon(d, hasTime: c.hour != nil)
    }
    private func canon(_ date: Date, hasTime: Bool) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = hasTime ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func writeToEK(_ e: EKReminder, from r: Reminder) {
        e.title = r.title
        e.notes = (r.notes?.isEmpty == false) ? r.notes : nil
        if let d = parseDate(r.dueDate) {
            let fields: Set<Calendar.Component> = (r.hasTime ?? false)
                ? [.year, .month, .day, .hour, .minute]
                : [.year, .month, .day]
            e.dueDateComponents = Calendar.current.dateComponents(fields, from: d)
        } else {
            e.dueDateComponents = nil
        }
        e.isCompleted = r.completed ?? false
        // Nudge is the SINGLE owner of recurrence: completing a repeating reminder
        // spawns its next occurrence in NudgeStore.toggleComplete. So we keep the
        // Apple mirror flat (no repeat rule) — otherwise Apple would auto-advance the
        // same repeat in parallel and we'd get duplicate occurrences. Repeats authored
        // in Apple are imported once via backfill/ekToRecurrence, then flattened here.
        e.recurrenceRules = nil
        // Link is two-way; only set when Nudge has one, never clear Apple's.
        if let u = r.url, !u.isEmpty, let url = URL(string: u) { e.url = url }
    }

    /// Copy a repeat rule / link from Apple into a Nudge reminder *only when Nudge
    /// is missing it* — backfills data that earlier syncs silently dropped, without
    /// ever clobbering a value the user set on the Nudge side.
    @discardableResult
    private func backfillFromApple(_ r: inout Reminder, from e: EKReminder) -> Bool {
        var changed = false
        if (r.recurrence == nil || r.recurrence?.freq == "none"), let rec = ekToRecurrence(e) {
            r.recurrence = rec; changed = true
        }
        if (r.url?.isEmpty ?? true), let u = e.url?.absoluteString, !u.isEmpty {
            r.url = u; changed = true
        }
        // Deliberately do NOT bump updatedAt — backfill is a cosmetic fill, and a
        // bumped timestamp would skew Nudge-vs-Apple conflict resolution.
        return changed
    }

    private func ekToRecurrence(_ e: EKReminder) -> Recurrence? {
        guard let rule = e.recurrenceRules?.first else { return nil }
        let freq: String
        switch rule.frequency {
        case .daily:   freq = "daily"
        case .weekly:  freq = "weekly"
        case .monthly: freq = "monthly"
        case .yearly:  freq = "yearly"
        @unknown default: freq = "daily"
        }
        let interval = rule.interval > 1 ? rule.interval : nil
        let until = rule.recurrenceEnd?.endDate.map { iso($0) }
        return Recurrence(freq: freq, interval: interval, until: until)
    }

    private func writeToNudge(_ r: inout Reminder, from e: EKReminder) {
        r.title = e.title ?? ""
        r.notes = (e.notes?.isEmpty == false) ? e.notes : nil
        if let c = e.dueDateComponents, let d = Calendar.current.date(from: c) {
            r.hasTime = c.hour != nil
            r.dueDate = iso(d)
        } else {
            r.dueDate = nil
            r.hasTime = nil
        }
        // Import a link added/changed in Apple; fill-only, never clears a Nudge link.
        if let u = e.url?.absoluteString, !u.isEmpty { r.url = u }
        if e.isCompleted {
            // Don't re-stamp "now" each sync when Apple has no completion date —
            // that was inflating "Done today" and the widget's all-done reading.
            if let cd = e.completionDate { r.completedAt = iso(cd) }
            else if r.completedAt == nil { r.completedAt = iso(Date()) }
            r.completed = true
        } else {
            r.completed = false
            r.completedAt = nil
        }
        r.updatedAt = iso(Date())
    }

    private func newNudgeReminder(from e: EKReminder) -> Reminder {
        var r = Reminder(
            id: "r" + String(UUID().uuidString.prefix(12)),
            title: e.title ?? "", notes: nil, dueDate: nil, hasTime: nil,
            listId: "reminders", priority: nudgePriority(e.priority),
            completed: false, completedAt: nil, recurrence: ekToRecurrence(e), subtasks: [],
            remindBefore: nil, tz: nil, createdAt: iso(Date()), updatedAt: iso(Date()),
            source: "apple", snoozedUntil: nil, dismissed: false)
        if let u = e.url?.absoluteString, !u.isEmpty { r.url = u }
        writeToNudge(&r, from: e)
        return r
    }

    private func ekPriority(_ p: String) -> Int {
        switch p { case "high": return 1; case "low": return 9; default: return 0 }
    }
    private func nudgePriority(_ p: Int) -> String {
        switch p { case 1...4: return "high"; case 6...9: return "low"; default: return "normal" }
    }
}
