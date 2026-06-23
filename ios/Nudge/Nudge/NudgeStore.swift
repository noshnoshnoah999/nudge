// NudgeStore.swift — Nudge (iOS)
// Loads/saves the shared Supabase `nudge_data` blob so iOS ⇄ web ⇄ cloud stay in sync.

import Foundation
import SwiftUI
import Combine
import WidgetKit
import UserNotifications

extension Notification.Name {
    /// Posted after local reminder data changes, so the EventKit mirror can push.
    static let nudgeDataChanged = Notification.Name("nudgeDataChanged")
}

@MainActor
final class NudgeStore: ObservableObject {
    @Published var reminders: [Reminder] = []
    @Published var lists: [ReminderList] = []
    @Published var smartLists: [SmartList] = []
    @Published var syncState: String = "Local"

    private var settings: [String: JSONValue]? = nil
    private var pushTask: Task<Void, Never>? = nil
    /// True from the moment a local edit is made until its debounced cloud push
    /// finishes. While true, an incoming cloud refresh must NOT overwrite local
    /// state — our edit hasn't been published yet and would be lost from view.
    private var hasPendingPush = false

    // Same Supabase project + anon key as the web app (anon key is public-tier).
    private let baseURL = "https://epaiazxcdcseijkhrncm.supabase.co"
    private let anon = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwYWlhenhjZGNzZWlqa2hybmNtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMjQ0MzQsImV4cCI6MjA5MjYwMDQzNH0.h2t_kFLZ_YPvuJlzPPiyXVbOnW4Ub_52hdaYosMoOus"
    private let userKey = "2631e558-19f1-4961-9502-d701f4b15826"

    private var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nudge_cache.json")
    }

    init() { loadCache() }

    // MARK: - Load
    private func loadCache() {
        if let d = try? Data(contentsOf: cacheURL),
           let blob = try? JSONDecoder().decode(NudgeData.self, from: d) {
            apply(blob)
        }
    }

    struct Row: Codable { var data: NudgeData }

    func refresh() async {
        guard let u = URL(string: "\(baseURL)/rest/v1/nudge_data?user_key=eq.\(userKey)&select=data") else { return }
        var req = URLRequest(url: u)
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let rows = try JSONDecoder().decode([Row].self, from: data)
            if let blob = rows.first?.data {
                if hasPendingPush || (blob.reminders == reminders && blob.lists == lists) {
                    // Either we have un-uploaded local edits (the older cloud copy
                    // would stomp them), or nothing actually changed — don't churn.
                    setSync("Synced")
                } else {
                    backupSnapshot("cloud")   // preserve current local before the cloud copy replaces it
                    apply(blob); cache(blob); setSync("Synced")
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        } catch {
            setSync("Offline")
        }
        syncPrepReminders()   // keep linked "prep" reminders (e.g. buy ginger ingredients) aligned
    }

    /// Publish syncState only when it actually changes — otherwise the 15s background
    /// poll re-renders every view observing the store (including an open edit sheet,
    /// which was dropping the title field's keyboard focus mid-edit).
    private func setSync(_ s: String) { if syncState != s { syncState = s } }

    private func apply(_ blob: NudgeData) {
        reminders = blob.reminders
        lists = blob.lists
        smartLists = blob.smartLists ?? []
        settings = blob.settings
    }
    private func cache(_ blob: NudgeData) {
        if let d = try? JSONEncoder().encode(blob) { try? d.write(to: cacheURL) }
    }

    // Created once on first access — backupSnapshot + lastBackup hit this on every
    // sync, so re-creating the dir each time was flagged as excessive I/O.
    private lazy var backupDir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Most recent local backup time + how many backups are retained — surfaced in
    /// Settings so the safety net is visible.
    var lastBackup: (date: Date, count: Int)? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]),
              !files.isEmpty else { return nil }
        let dates = files.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        guard let newest = dates.max() else { return nil }
        return (newest, files.count)
    }

    /// Snapshot current reminders to a rotating local backup (keeps the most recent
    /// 60) BEFORE anything overwrites them, so a bad sync/merge can be rolled back.
    /// Throttled to at most one auto-backup per 10 minutes so a burst of edits (each
    /// of which triggers a sync) can't churn the rotation and flush real history in
    /// minutes. Best-effort and silent.
    func backupSnapshot(_ reason: String = "auto", force: Bool = false) {
        guard !reminders.isEmpty else { return }
        if !force, let last = lastBackup?.date, Date().timeIntervalSince(last) < 600 { return }
        let blob = NudgeData(reminders: reminders, lists: lists, smartLists: smartLists, settings: settings)
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = backupDir.appendingPathComponent("nudge_\(reason)_\(ts).json")
        guard let d = try? JSONEncoder().encode(blob) else { return }
        try? d.write(to: url)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let sorted = files.sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
            for old in sorted.dropFirst(60) { try? FileManager.default.removeItem(at: old) }
        }
    }

    struct BackupInfo: Identifiable {
        var id: String { url.path }
        let url: URL
        let date: Date
        let count: Int
    }

    /// Decodable backups on disk, newest first — for the Settings restore screen.
    func listBackups() -> [BackupInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return files.compactMap { u -> BackupInfo? in
            guard u.pathExtension == "json",
                  let d = try? Data(contentsOf: u),
                  let blob = try? JSONDecoder().decode(NudgeData.self, from: d) else { return nil }
            let date = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return BackupInfo(url: u, date: date, count: blob.reminders.count)
        }.sorted { $0.date > $1.date }
    }

    /// Replace current data with a backup. Snapshots the current state first (forced,
    /// bypassing the throttle) so a restore is itself undoable.
    func restoreBackup(_ info: BackupInfo) {
        guard let d = try? Data(contentsOf: info.url),
              let blob = try? JSONDecoder().decode(NudgeData.self, from: d) else { return }
        backupSnapshot("pre-restore", force: true)
        apply(blob)
        persist()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Save (debounced upsert)
    struct Payload: Codable { var user_key: String; var data: NudgeData; var updated_at: String }

    func persist(notify: Bool = true) {
        let blob = NudgeData(reminders: reminders, lists: lists, smartLists: smartLists, settings: settings)
        cache(blob)
        setSync("Syncing…")
        hasPendingPush = true
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            await self?.push(blob)
        }
        // Let the EventKit mirror know local data changed (it debounces). The sync
        // engine's own write-backs pass notify:false to avoid a feedback loop.
        if notify { NotificationCenter.default.post(name: .nudgeDataChanged, object: nil) }
        WidgetCenter.shared.reloadAllTimelines()
    }
    /// Push the current state to the cloud RIGHT NOW, awaited. The debounced persist()
    /// is fine for foreground edits, but a notification action (Complete/Snooze) is
    /// handled in the background — iOS suspends the app the moment the async handler
    /// returns, before the 700ms debounce fires, so that change would be lost and then
    /// stomped by the next refresh(). Call this to flush before the handler returns.
    func persistNow() async {
        pushTask?.cancel()
        let blob = NudgeData(reminders: reminders, lists: lists, smartLists: smartLists, settings: settings)
        cache(blob)
        hasPendingPush = true
        await push(blob)
    }

    private func push(_ blob: NudgeData) async {
        defer { hasPendingPush = false }
        guard let u = URL(string: "\(baseURL)/rest/v1/nudge_data") else { return }
        var req = URLRequest(url: u); req.httpMethod = "POST"
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anon)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        let payload = Payload(user_key: userKey, data: blob, updated_at: iso(Date()))
        req.httpBody = try? JSONEncoder().encode(payload)
        do { _ = try await URLSession.shared.data(for: req); setSync("Synced") }
        catch { setSync("Offline") }
    }

    // MARK: - Mutations
    func toggleComplete(_ r: Reminder) {
        guard let i = reminders.firstIndex(where: { $0.id == r.id }) else { return }
        // A nightly routine never "completes" — ticking it means "did it tonight", so it
        // rolls forward in place (no spawned copies). Untick on a routine is a no-op.
        if (reminders[i].routine ?? false) && !(reminders[i].completed ?? false) {
            // Anchor on the night it was due (not "now") so a list-tick of a lapsed routine
            // schedules the same next occurrence as the morning check-in.
            routineDidIt(r.id, night: parseDate(reminders[i].dueDate) ?? Date())
            return
        }
        let nowComplete = !(reminders[i].completed ?? false)
        reminders[i].completed = nowComplete
        reminders[i].completedAt = nowComplete ? iso(Date()) : nil
        reminders[i].snoozedUntil = nil
        reminders[i].updatedAt = iso(Date())
        if nowComplete { clearNotifications(for: r.id) }   // drop any delivered/pending alert
        // Completing a repeating reminder spawns its next occurrence.
        if nowComplete, let rec = reminders[i].recurrence, rec.freq != "none",
           let next = nextOccurrence(after: reminders[i].dueDate, rec: rec) {
            var copy = reminders[i]
            copy.id = "r" + String(UUID().uuidString.prefix(12))
            copy.completed = false
            copy.completedAt = nil
            copy.dueDate = next
            copy.createdAt = iso(Date())
            copy.updatedAt = iso(Date())
            reminders.insert(copy, at: 0)
        }
        persist()
    }

    /// Advance a due date to the next FUTURE occurrence per the recurrence rule.
    func nextOccurrence(after dueStr: String?, rec: Recurrence) -> String? {
        guard let due = parseDate(dueStr) else { return nil }
        let cal = Calendar.current
        let step = max(1, rec.interval ?? 1)
        let comp: Calendar.Component
        switch rec.freq {
        case "hourly": comp = .hour
        case "daily": comp = .day
        case "weekly": comp = .weekOfYear
        case "monthly": comp = .month
        case "yearly": comp = .year
        default: return nil
        }
        var next = due
        var guardCount = 0
        repeat {
            next = cal.date(byAdding: comp, value: step, to: next) ?? next
            guardCount += 1
        } while next <= Date() && guardCount < 2000
        // Respect an "end repeat" date.
        if let u = parseDate(rec.until), next > u { return nil }
        return iso(next)
    }

    /// Open reminders in the Shopping list (the "buy" reminders), soonest first.
    func buyReminders() -> [Reminder] {
        open().filter { $0.listIdOrDefault == "shopping" }
            .sorted { (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture) }
    }

    // MARK: - Nightly routine (KP / Epiduo morning check-in)

    /// Start of the day `n` days from today (for the check-in's quick reschedule buttons).
    func dayFromNow(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    /// Current repeat interval (in days) for a routine reminder, honouring escalation
    /// phases (the first phase whose `until` is still in the future, else the open one).
    func routineIntervalDays(_ r: Reminder) -> Int {
        if let steps = r.escalation, !steps.isEmpty {
            let now = Date()
            for s in steps {
                if let u = parseDate(s.until) { if now < u { return max(1, s.everyDays) } }
                else { return max(1, s.everyDays) }
            }
            return max(1, steps.last?.everyDays ?? 1)
        }
        if let rec = r.recurrence {
            switch rec.freq {
            case "daily":  return max(1, rec.interval ?? 1)
            case "weekly": return 7 * max(1, rec.interval ?? 1)
            default: break
            }
        }
        return 1
    }

    /// Routine reminders that lapsed on a PREVIOUS night (open, due before today) — the
    /// ones the morning check-in asks about.
    func lapsedRoutinesForCheckin() -> [Reminder] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return reminders.filter { r in
            (r.routine ?? false) && !(r.completed ?? false) && !(r.dismissed ?? false)
                && (parseDate(r.dueDate).map { cal.startOfDay(for: $0) < today } ?? false)
        }.sorted { (parseDate($0.dueDate) ?? .distantPast) < (parseDate($1.dueDate) ?? .distantPast) }
    }

    /// The evening time-of-day a routine fires at (from its current due date; default 21:00).
    private func routineEveningComponents(_ r: Reminder) -> (h: Int, m: Int) {
        if let d = parseDate(r.dueDate) {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 21, c.minute ?? 0)
        }
        return (21, 0)
    }

    /// Roll a routine reminder forward one cycle: next occurrence after `night`, stepping
    /// by the active interval AT LEAST ONCE (so ticking it before its due time still
    /// advances), keeping its evening time-of-day. Stays open; `completedAt` is stamped so
    /// the tick counts toward Done-today. Pure mutation — no persist (caller decides).
    func advanceRoutine(_ r: inout Reminder, night: Date) {
        let cal = Calendar.current
        let interval = routineIntervalDays(r)
        let (h, m) = routineEveningComponents(r)
        var c = cal.dateComponents([.year, .month, .day], from: night)
        c.hour = h; c.minute = m
        var next = cal.date(from: c) ?? night
        var guardN = 0
        repeat {
            next = cal.date(byAdding: .day, value: interval, to: next) ?? next
            guardN += 1
        } while next <= Date() && guardN < 2000
        r.dueDate = iso(next)
        r.completed = false
        r.completedAt = iso(Date())
        r.snoozedUntil = nil
        r.updatedAt = iso(Date())
    }

    /// "I did it" → leave a "done on this day" record in the Completed list, then advance.
    func routineDidIt(_ id: String, night: Date) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        let snap = completedSnapshot(of: reminders[i], doneOn: night)
        advanceRoutine(&reminders[i], night: night)
        reminders[i].completedAt = nil   // the snapshot is the completion record now (no double-count)
        reminders.insert(snap, at: 0)
        clearNotifications(for: id)
        persist()
        syncPrepReminders()   // a prep linked to this routine follows its new date
    }

    /// A one-off, completed clone of a repeating reminder/routine — the historical "I did it
    /// on this day" entry that shows in the Completed list. Not repeating itself, so it just
    /// sits in history (and auto-clears with the usual 3-week purge).
    func completedSnapshot(of r: Reminder, doneOn night: Date) -> Reminder {
        var s = r
        s.id = "r" + String(UUID().uuidString.prefix(12))
        s.completed = true
        s.completedAt = iso(Date())
        s.dueDate = iso(night)        // the occurrence that was completed
        s.recurrence = nil
        s.routine = false
        s.escalation = nil
        s.snoozedUntil = nil
        s.pinned = false
        s.createdAt = iso(Date())
        s.updatedAt = iso(Date())
        return s
    }

    /// "Not yet" → move the routine to a chosen day, keeping its evening time.
    func routineRescheduleTo(_ id: String, day: Date) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        let cal = Calendar.current
        let (h, m) = routineEveningComponents(reminders[i])
        var c = cal.dateComponents([.year, .month, .day], from: day)
        c.hour = h; c.minute = m
        reminders[i].dueDate = iso(cal.date(from: c) ?? day)
        reminders[i].completed = false
        reminders[i].snoozedUntil = nil
        reminders[i].updatedAt = iso(Date())
        clearNotifications(for: id)
        persist()
        syncPrepReminders()   // a prep linked to this routine follows its new date
    }

    /// Adaptive "skin's ready" step-up: shorten the current open-ended phase's interval
    /// by one notch (e.g. every 3 days → 2 → 1) and schedule the next "ready?" check.
    func routineStepUp(_ id: String, askAgainInDays: Int = 14) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        var steps = reminders[i].escalation ?? [EscalationStep(everyDays: routineIntervalDays(reminders[i]), until: nil)]
        // Shorten the final (open) phase; if it has an explicit until, append a faster open phase.
        if let last = steps.indices.last {
            if steps[last].until == nil {
                steps[last].everyDays = max(1, steps[last].everyDays - 1)
            } else {
                steps.append(EscalationStep(everyDays: max(1, steps[last].everyDays - 1), until: nil))
            }
        }
        reminders[i].escalation = steps
        reminders[i].escalateAskNext = iso(Calendar.current.date(byAdding: .day, value: askAgainInDays, to: Date()) ?? Date())
        reminders[i].updatedAt = iso(Date())
        persist()
    }

    /// Push the next "ready to step up?" prompt out without changing the interval.
    func routineSnoozeAsk(_ id: String, days: Int = 14) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].escalateAskNext = iso(Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
        reminders[i].updatedAt = iso(Date())
        persist()
    }

    /// Routine reminders whose adaptive "ready to step up?" date has arrived.
    func routinesDueForStepUpAsk() -> [Reminder] {
        let now = Date()
        return reminders.filter { r in
            (r.routine ?? false) && !(r.dismissed ?? false)
                && (parseDate(r.escalateAskNext).map { $0 <= now } ?? false)
        }
    }

    /// Reinterpret a device-local wall time as the same wall time in `tz`.
    func wallToUTC(_ date: Date, tz: String) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? .current
        return cal.date(from: comps) ?? date
    }
    func list(for id: String?) -> ReminderList? { lists.first { $0.id == (id ?? "reminders") } }

    /// The just-deleted reminder, kept briefly so the UI can offer Undo. Its photos
    /// are not purged until the undo window passes (see `finalizeDelete`).
    @Published var recentlyDeleted: Reminder?

    func deleteReminder(_ r: Reminder) {
        finalizeDelete()                 // commit any earlier pending deletion first
        reminders.removeAll { $0.id == r.id }
        clearNotifications(for: r.id)    // clear any delivered/pending alert
        recentlyDeleted = r              // hold for Undo; images purged on finalize
        persist()
    }

    /// Bring back the last swipe/menu-deleted reminder.
    func undoDelete() {
        guard let r = recentlyDeleted else { return }
        if !reminders.contains(where: { $0.id == r.id }) { reminders.insert(r, at: 0) }
        recentlyDeleted = nil
        persist()
    }

    /// Commit a pending deletion: purge its photos and drop the Undo handle.
    func finalizeDelete() {
        if let r = recentlyDeleted { ImageStore.deleteAll(for: r.id); recentlyDeleted = nil }
    }

    /// Auto-tidy: drop reminders that were COMPLETED more than `days` ago (default 3
    /// weeks). Nightly routines are never "completed" (they roll forward), so they're
    /// untouched. Completed reminders with no completedAt timestamp are left alone (we
    /// can't tell their age). Mirrors a manual delete: clears photos + alerts + pushes.
    @discardableResult
    func purgeOldCompleted(olderThan days: Int = 21) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let stale = reminders.filter { r in
            guard r.isCompleted, let done = parseDate(r.completedAt) else { return false }
            return done < cutoff
        }
        guard !stale.isEmpty else { return 0 }
        for r in stale { ImageStore.deleteAll(for: r.id); clearNotifications(for: r.id) }
        let ids = Set(stale.map { $0.id })
        reminders.removeAll { ids.contains($0.id) }
        persist()
        return stale.count
    }

    /// Keep every "prep" reminder (one with `prepFor` set) parked `prepDaysBefore` days
    /// before its target's due date, at prepHour:prepMinute. If that lands in the past
    /// (the target is due very soon / overdue), roll forward by the target's interval to
    /// the next future window — so we never surface a useless overdue prep. When the date
    /// actually changes (target advanced or was rescheduled), re-open it for the new cycle.
    func syncPrepReminders() {
        let cal = Calendar.current
        let now = Date()
        var changed = false
        for i in reminders.indices {
            guard let tid = reminders[i].prepFor,
                  let target = reminders.first(where: { $0.id == tid }),
                  let tdue = parseDate(target.dueDate) else { continue }
            let days = max(0, reminders[i].prepDaysBefore ?? 2)
            let hour = reminders[i].prepHour ?? 17
            let minute = reminders[i].prepMinute ?? 30
            let interval = max(1, routineIntervalDays(target))   // weekly make → 7
            var anchor = tdue
            var want = now
            for _ in 0..<366 {   // safety bound
                let base = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: anchor)) ?? anchor
                var c = cal.dateComponents([.year, .month, .day], from: base)
                c.hour = hour; c.minute = minute
                want = cal.date(from: c) ?? base
                if want > now { break }
                anchor = cal.date(byAdding: .day, value: interval, to: anchor) ?? anchor
            }
            let wantIso = iso(want)
            if reminders[i].dueDate != wantIso {
                reminders[i].dueDate = wantIso
                reminders[i].hasTime = true
                reminders[i].completed = false        // new cycle → buy again
                reminders[i].completedAt = nil
                reminders[i].snoozedUntil = nil
                reminders[i].updatedAt = iso(now)
                changed = true
            }
        }
        if changed { persist() }
    }

    /// Snooze a reminder forward by `minutes` from now — it drops out of Overdue and
    /// re-alerts when the time arrives. Clears any alert already sitting in the centre.
    func snooze(_ r: Reminder, minutes: Int) {
        guard let i = reminders.firstIndex(where: { $0.id == r.id }) else { return }
        let when = Date().addingTimeInterval(Double(minutes) * 60)
        // Routines derive their evening time from dueDate — moving it would permanently
        // shift the schedule, so only set snoozedUntil (notifications fire at the later
        // of due-based and snoozedUntil).
        if !(reminders[i].routine ?? false) {
            reminders[i].dueDate = iso(when)
            reminders[i].hasTime = true
            reminders[i].tz = nil
        }
        reminders[i].snoozedUntil = iso(when)
        reminders[i].updatedAt = iso(Date())
        clearNotifications(for: r.id)
        persist()
    }

    /// Remove a reminder's notification — both pending (scheduled) and delivered
    /// (already shown). Fixes lingering alerts after delete / complete / snooze.
    private func clearNotifications(for id: String) {
        let key = "nudge-\(id)"
        let c = UNUserNotificationCenter.current()
        c.removeDeliveredNotifications(withIdentifiers: [key])
        c.removePendingNotificationRequests(withIdentifiers: [key])
    }

    /// Find the next minute-slot at/after `desired` that no other timed reminder
    /// already occupies — so two reminders don't land at the exact same time.
    func nextFreeSlot(_ desired: Date, excluding id: String? = nil, stepMinutes: Int = 15) -> Date {
        let cal = Calendar.current
        func key(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            return "\(c.year!)-\(c.month!)-\(c.day!)-\(c.hour!)-\(c.minute!)"
        }
        var taken = Set<String>()
        for r in reminders where !(r.completed ?? false) && r.id != id && (r.hasTime ?? false) {
            if let d = parseDate(r.dueDate) { taken.insert(key(d)) }
        }
        var cand = desired, guardN = 0
        while taken.contains(key(cand)) && guardN < 96 {
            cand = cal.date(byAdding: .minute, value: stepMinutes, to: cand) ?? cand
            guardN += 1
        }
        return cand
    }

    /// A smart suggested time for a reminder: keyword hints in the title first
    /// (gym/lunch/dinner/meds…), then the user's own most-used hour, then a sensible
    /// default for the current part of day. Always future (if today) and collision-free.
    func recommendedTime(title: String, on day: Date, excluding id: String? = nil) -> Date {
        let cal = Calendar.current
        let lower = title.lowercased()
        var hour: Int?

        let hints: [(words: [String], hour: Int)] = [
            (["breakfast", "wake", "morning", "gym", "run", "jog", "med", "vitamin", "shower", "walk"], 8),
            (["lunch", "midday", "noon"], 12),
            (["study", "work", "meeting", "call", "email", "afternoon", "errand"], 15),
            (["dinner", "evening", "cook", "groceries"], 18),
            (["night", "bed", "sleep", "skincare", "stretch", "journal", "read"], 21),
        ]
        for h in hints where h.words.contains(where: { lower.contains($0) }) { hour = h.hour; break }

        // Learn the user's most common reminder hour.
        if hour == nil {
            var counts: [Int: Int] = [:]
            for r in reminders where !(r.completed ?? false) && (r.hasTime ?? false) {
                if let d = parseDate(r.dueDate) { counts[cal.component(.hour, from: d), default: 0] += 1 }
            }
            hour = counts.max { $0.value < $1.value }?.key
        }

        let now = Date()
        if hour == nil {
            let h = cal.component(.hour, from: now)
            hour = h < 9 ? 9 : (h < 16 ? h + 1 : (h < 20 ? 19 : 9))
        }

        var c = cal.dateComponents([.year, .month, .day], from: day)
        c.hour = hour; c.minute = 0
        var desired = cal.date(from: c) ?? day
        if cal.isDateInToday(day) && desired < now {
            c.hour = min(cal.component(.hour, from: now) + 1, 22); c.minute = 0
            desired = cal.date(from: c) ?? now.addingTimeInterval(3600)
        }
        return nextFreeSlot(desired, excluding: id)
    }

    /// Move a single reminder to a new date/time.
    func reschedule(_ id: String, to date: Date) {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[i].dueDate = iso(date)
        reminders[i].hasTime = true
        reminders[i].snoozedUntil = nil
        reminders[i].tz = nil
        reminders[i].updatedAt = iso(Date())
        persist()
    }

    /// Assign a reminder to a named section within its list (nil = ungrouped).
    func setSection(_ reminderId: String, to section: String?) {
        guard let i = reminders.firstIndex(where: { $0.id == reminderId }) else { return }
        reminders[i].section = (section?.isEmpty == false) ? section : nil
        reminders[i].updatedAt = iso(Date())
        persist()
    }

    // MARK: - Smart reschedule
    /// Propose new slots for all overdue (non-routine) reminders WITHOUT applying — the
    /// preview sheet shows these and the user confirms. Routines have their own check-in.
    func planSmartReschedule() -> [RescheduleChange] {
        let overdue = reminders.filter { isOverdue($0) && !($0.routine ?? false) }
        CalendarService.shared.refresh()   // freshest events so we avoid your busy times
        return SmartScheduler.plan(overdue, busy: CalendarService.shared.busyIntervals())
    }

    /// AI-first Smart Reschedule: if an Anthropic API key is set, ask Claude to spread the
    /// overdue pile intelligently (avoiding calendar events); otherwise — or on any failure —
    /// fall back to the built-in heuristic planner. Both return a preview to confirm.
    func planSmartRescheduleAI() async -> [RescheduleChange] {
        let overdue = reminders.filter { isOverdue($0) && !($0.routine ?? false) }
        guard !overdue.isEmpty else { return [] }
        CalendarService.shared.refresh()
        let busy = CalendarService.shared.busyIntervals()
        let key = UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
        if !key.isEmpty {
            let model = UserDefaults.standard.string(forKey: "ai_reschedule_model") ?? AIScheduler.defaultModel
            if let ai = try? await AIScheduler.plan(overdue: overdue, busy: busy, now: Date(),
                                                    apiKey: key, model: model), !ai.isEmpty {
                return ai
            }
        }
        return SmartScheduler.plan(overdue, busy: busy)
    }

    /// Apply a user-approved subset of proposed reschedule changes.
    @discardableResult
    func applyReschedule(_ changes: [RescheduleChange], auto: Bool = false) -> [RescheduleChange] {
        guard !changes.isEmpty else { return [] }
        for c in changes {
            guard let i = reminders.firstIndex(where: { $0.id == c.id }) else { continue }
            reminders[i].dueDate = c.newDue
            reminders[i].hasTime = true
            reminders[i].tz = nil
            reminders[i].snoozedUntil = nil
            reminders[i].updatedAt = iso(Date())
        }
        persist()
        RescheduleLog.add(RescheduleLogEntry(id: UUID().uuidString, date: Date(), auto: auto, changes: changes))
        return changes
    }

    // MARK: - Targeted triage (the reminders you keep avoiding)
    /// Open reminders Smart Reschedule has had to move 3+ times — i.e. they keep
    /// lapsing. Excludes ones you recently chose to "Keep". Most-moved first.
    func stuckReminders(threshold: Int = 3) -> [(r: Reminder, count: Int)] {
        let counts = RescheduleLog.counts()
        let kept = UserDefaults.standard.dictionary(forKey: "triageKeptAt") as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        return reminders.compactMap { r -> (Reminder, Int)? in
            if (r.completed ?? false) || (r.dismissed ?? false) || (r.routine ?? false) { return nil }
            let c = counts[r.id] ?? 0
            guard c >= threshold else { return nil }
            if let k = kept[r.id], now - k < 14 * 86400 { return nil }   // acknowledged in last 14 days
            return (r, c)
        }.sorted { $0.1 > $1.1 }
    }

    func stuckCount() -> Int { stuckReminders().count }

    /// Completed reminders, most-recently-completed first.
    func completedReminders() -> [Reminder] {
        reminders.filter { $0.completed ?? false }
            .sorted { (parseDate($0.completedAt) ?? .distantPast) > (parseDate($1.completedAt) ?? .distantPast) }
    }

    /// "Keep" — affirm a stuck reminder; don't flag it again for 14 days.
    func acknowledgeKeep(_ id: String) {
        var kept = UserDefaults.standard.dictionary(forKey: "triageKeptAt") as? [String: Double] ?? [:]
        kept[id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(kept, forKey: "triageKeptAt")
    }

    func undoReschedule(_ changes: [RescheduleChange]) {
        for c in changes {
            guard let i = reminders.firstIndex(where: { $0.id == c.id }) else { continue }
            reminders[i].dueDate = c.oldDue
            reminders[i].hasTime = (parseDate(c.oldDue) != nil) ? reminders[i].hasTime : nil
            reminders[i].updatedAt = iso(Date())
        }
        persist()
    }

    func saveReminder(editing: Reminder?, title: String, notes: String,
                      hasDue: Bool, due: Date, hasTime: Bool,
                      listId: String, priority: String,
                      recurrence: Recurrence? = nil, tz: String? = nil,
                      url: String? = nil, location: String? = nil,
                      lat: Double? = nil, lng: Double? = nil,
                      pinned: Bool = false, remindBefores: [Int] = [],
                      subtasks: [Subtask] = [], routine: Bool = false,
                      escalation: [EscalationStep] = [], reviewFrequency: Bool = false,
                      idForNew: String? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // With a pinned timezone, the picked wall time is interpreted in that zone.
        let dueStr: String?
        if hasDue {
            if hasTime {
                let instant = (tz != nil) ? wallToUTC(due, tz: tz!) : due
                dueStr = iso(instant)
            } else {
                dueStr = iso(Calendar.current.startOfDay(for: due))
            }
        } else {
            dueStr = nil
        }
        let cleanURL = url?.trimmingCharacters(in: .whitespaces)
        let cleanLoc = location?.trimmingCharacters(in: .whitespaces)
        let rec = (recurrence?.freq == "none") ? nil : recurrence
        if let existing = editing, let i = reminders.firstIndex(where: { $0.id == existing.id }) {
            reminders[i].title = cleanTitle
            reminders[i].notes = notes
            reminders[i].dueDate = dueStr
            reminders[i].hasTime = hasDue ? hasTime : nil
            reminders[i].listId = listId
            reminders[i].priority = priority
            reminders[i].recurrence = rec
            reminders[i].tz = (hasDue && hasTime) ? tz : nil
            reminders[i].url = (cleanURL?.isEmpty == false) ? cleanURL : nil
            reminders[i].location = (cleanLoc?.isEmpty == false) ? cleanLoc : nil
            reminders[i].lat = (cleanLoc?.isEmpty == false) ? lat : nil
            reminders[i].lng = (cleanLoc?.isEmpty == false) ? lng : nil
            reminders[i].pinned = pinned ? true : nil
            let early = Array(Set(remindBefores.filter { $0 > 0 })).sorted(by: >)
            reminders[i].remindBefores = early.isEmpty ? nil : early
            reminders[i].remindBefore = early.min()   // legacy mirror for older readers
            reminders[i].subtasks = subtasks.isEmpty ? nil : subtasks
            reminders[i].routine = routine ? true : nil
            reminders[i].escalation = escalation.isEmpty ? nil : escalation
            if reviewFrequency {
                if reminders[i].escalateAskNext == nil {   // start the review cycle; keep an existing pending date
                    reminders[i].escalateAskNext = iso(Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date())
                }
            } else { reminders[i].escalateAskNext = nil }
            reminders[i].updatedAt = iso(Date())
        } else {
            let r = Reminder(
                id: idForNew ?? ("r" + String(UUID().uuidString.prefix(12))),
                title: cleanTitle, notes: notes, dueDate: dueStr,
                hasTime: hasDue ? hasTime : nil, listId: listId, priority: priority,
                completed: false, completedAt: nil, recurrence: rec,
                subtasks: subtasks.isEmpty ? [] : subtasks,
                remindBefore: Array(Set(remindBefores.filter { $0 > 0 })).min(),
                remindBefores: { let e = Array(Set(remindBefores.filter { $0 > 0 })).sorted(by: >); return e.isEmpty ? nil : e }(),
                tz: (hasDue && hasTime) ? tz : nil,
                url: (cleanURL?.isEmpty == false) ? cleanURL : nil,
                location: (cleanLoc?.isEmpty == false) ? cleanLoc : nil,
                lat: (cleanLoc?.isEmpty == false) ? lat : nil,
                lng: (cleanLoc?.isEmpty == false) ? lng : nil,
                createdAt: iso(Date()), updatedAt: iso(Date()),
                source: "manual", snoozedUntil: nil, dismissed: false,
                pinned: pinned ? true : nil,
                routine: routine ? true : nil,
                escalation: escalation.isEmpty ? nil : escalation,
                escalateAskNext: reviewFrequency ? iso(Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()) : nil)
            reminders.insert(r, at: 0)
        }
        persist()
    }

    // MARK: - Grouping
    func open() -> [Reminder] { reminders.filter { !($0.completed ?? false) && !($0.dismissed ?? false) } }

    func isOverdue(_ r: Reminder) -> Bool {
        guard !(r.completed ?? false), !(r.dismissed ?? false), let d = parseDate(r.dueDate) else { return false }
        if let s = parseDate(r.snoozedUntil), s > Date() { return false }
        // A date-only reminder (no time) isn't overdue until its whole day has passed —
        // otherwise it reads as "overdue" from 00:01 on the very day it's due.
        let cal = Calendar.current
        let cutoff = (r.hasTime ?? false) ? d : (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: d)) ?? d)
        return cutoff < Date()
    }
    func overdueCount() -> Int { reminders.filter { isOverdue($0) }.count }

    struct ReminderSection: Identifiable { var id: String; var title: String; var items: [Reminder] }

    func sections(listId: String? = nil) -> [ReminderSection] {
        var rs = open()
        if let lid = listId { rs = rs.filter { $0.listIdOrDefault == lid } }
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var overdue: [Reminder] = [], todayItems: [Reminder] = [], upcoming: [Reminder] = [], nodate: [Reminder] = []
        for r in rs {
            guard let d = parseDate(r.dueDate) else { nodate.append(r); continue }
            if let s = parseDate(r.snoozedUntil), s > now { upcoming.append(r); continue }
            // Use the same rule as isOverdue() so date-only items don't show as
            // overdue on the day they're due.
            if isOverdue(r) { overdue.append(r) }
            else if cal.startOfDay(for: d) == today { todayItems.append(r) }
            else { upcoming.append(r) }
        }
        // High floats to the top of a section, Low sinks to the bottom; ties by date.
        let prank: (Reminder) -> Int = { $0.priorityOrNormal == "high" ? 0 : $0.priorityOrNormal == "low" ? 2 : 1 }
        let byDate: (Reminder, Reminder) -> Bool = {
            let ra = prank($0), rb = prank($1)
            if ra != rb { return ra < rb }
            return (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture)
        }
        // No-Date items have no date to tie-break on, but priority should still order them.
        let byPriority: (Reminder, Reminder) -> Bool = { prank($0) < prank($1) }
        // Upcoming reads as a timeline — date first, priority only breaks ties — so a
        // far-future High (e.g. a 2027 reminder) doesn't sit above next week's items.
        let byDateThenPriority: (Reminder, Reminder) -> Bool = {
            let da = parseDate($0.dueDate) ?? .distantFuture, db = parseDate($1.dueDate) ?? .distantFuture
            if da != db { return da < db }
            return prank($0) < prank($1)
        }
        var out: [ReminderSection] = []
        if !overdue.isEmpty   { out.append(ReminderSection(id: "overdue",  title: "Overdue",  items: overdue.sorted(by: byDate))) }
        if !todayItems.isEmpty { out.append(ReminderSection(id: "today",   title: "Today",    items: todayItems.sorted(by: byDate))) }
        if !upcoming.isEmpty  { out.append(ReminderSection(id: "upcoming", title: "Upcoming", items: upcoming.sorted(by: byDateThenPriority))) }
        if !nodate.isEmpty    { out.append(ReminderSection(id: "nodate",   title: "No Date",  items: nodate.sorted(by: byPriority))) }
        return out
    }

    /// Every open reminder dated today — including ones already past their time
    /// (still "today", just overdue). Sorted EARLIEST DUE FIRST so the day reads top-to-
    /// bottom in time order; priority only breaks ties between same-time reminders.
    func todayReminders() -> [Reminder] {
        let cal = Calendar.current
        let prank: (Reminder) -> Int = { $0.priorityOrNormal == "high" ? 0 : $0.priorityOrNormal == "low" ? 2 : 1 }
        return open().filter {
            guard let d = parseDate($0.dueDate) else { return false }
            if let s = parseDate($0.snoozedUntil), s > Date() { return false }
            return cal.isDateInToday(d)
        }.sorted {
            let da = parseDate($0.dueDate) ?? .distantFuture, db = parseDate($1.dueDate) ?? .distantFuture
            if da != db { return da < db }
            return prank($0) < prank($1)
        }
    }

    /// Reminders for the Overdue page: due on a PREVIOUS calendar day. A reminder due
    /// earlier *today* (time already passed) stays on the Today page — it only lands here
    /// once midnight rolls it into a past day. Excludes completed/dismissed/snoozed-ahead.
    func pastDayOverdue() -> [Reminder] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let prank: (Reminder) -> Int = { $0.priorityOrNormal == "high" ? 0 : $0.priorityOrNormal == "low" ? 2 : 1 }
        return open().filter {
            guard let d = parseDate($0.dueDate) else { return false }
            if let s = parseDate($0.snoozedUntil), s > Date() { return false }
            return cal.startOfDay(for: d) < today
        }.sorted {
            let ra = prank($0), rb = prank($1)
            if ra != rb { return ra < rb }
            return (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture)
        }
    }
    func pastDayOverdueCount() -> Int { pastDayOverdue().count }

    /// Open reminders the user pinned to the Home dashboard, high priority first.
    func pinnedReminders() -> [Reminder] {
        // Chronological — earliest due first (no-date items last); priority only breaks ties.
        let prank: (Reminder) -> Int = { $0.priorityOrNormal == "high" ? 0 : $0.priorityOrNormal == "low" ? 2 : 1 }
        return open().filter { $0.pinned == true }.sorted {
            let da = parseDate($0.dueDate) ?? .distantFuture, db = parseDate($1.dueDate) ?? .distantFuture
            if da != db { return da < db }
            return prank($0) < prank($1)
        }
    }
}

// MARK: - Date helpers (file-scope, shared across the module)
private let isoWithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()
func parseDate(_ s: String?) -> Date? {
    guard let s = s, !s.isEmpty else { return nil }
    return isoWithFraction.date(from: s) ?? isoPlain.date(from: s)
}
func iso(_ d: Date) -> String { isoWithFraction.string(from: d) }

func recurText(_ rec: Recurrence) -> String {
    let n = max(1, rec.interval ?? 1)
    let unit: String
    switch rec.freq {
    case "hourly":  unit = n == 1 ? "hour" : "hours"
    case "daily":   unit = n == 1 ? "day" : "days"
    case "weekly":  unit = n == 1 ? "week" : "weeks"
    case "monthly": unit = n == 1 ? "month" : "months"
    case "yearly":  unit = n == 1 ? "year" : "years"
    default: return ""
    }
    let base = n == 1 ? "Every \(unit)" : "Every \(n) \(unit)"
    if let u = parseDate(rec.until) {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return base + " until " + f.string(from: u)
    }
    return base
}

/// Short city tag from an IANA id, e.g. "Asia/Tokyo" → "Tokyo".
func tzCity(_ id: String) -> String {
    id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
}
