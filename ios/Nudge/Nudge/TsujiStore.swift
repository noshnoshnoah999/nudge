// TsujiStore.swift — Nudge (iOS + Mac Catalyst)
// Tsuji Action Banner, step 2 — the engine.
//
// Spec: TSUJI_ACTION_BANNER_SPEC.md. Noah's decisions on top of it:
// HANDOFF_2026-10-29_tsuji-banner.md (that file wins where they differ).
//
// What this does:
//  • Reads the 13 action events from the "Tsuji Plan" calendar by iCalendar UID
//    (calendarItemExternalIdentifier — Test 0 proved this works on iPhone and Mac, 1 Nov 2026).
//  • Works out each item's status from the CALENDAR DATE in the device's time zone.
//  • Clears an item only through clear(uid:typed:) after the exact phrase is typed.
//  • Treats the Calendar title as the source of truth (spec section 7); the local records are
//    only a cache plus the alarm backup used for undo.
//
// SAFETY:
//  • Every Calendar write goes through saveToCalendar(_:calendar:), which re-checks
//    TsujiPlan.calendarWritesEnabled AND the guardrails on the event itself before saving.
//    There is no other call to EKEventStore.save in this file — keep it that way.
//  • Nudge never changes an event's date, calendar or recurrence, never deletes or creates
//    events, and never edits an event with invitees.
//  • A clear made while saving is switched off (write == .dryRun) can NEVER turn into a real
//    Calendar write later: once saving is switched on, dry-run clears are simply forgotten.

import Foundation
import EventKit
import Combine

@MainActor
final class TsujiStore: ObservableObject {
    static let shared = TsujiStore()

    // MARK: - Test-mode-only entries (step 2, tests 8 and 9)

    /// A made-up UID that exists in no calendar → shows the "Missing from calendar" row.
    static let testMissingUID = "tsuji-plan-99-made-up-test@nudge.invalid"
    /// UID 01 — the 16 Jan 2027 open campus, which has an invitee (Noah's mum). Shown ONLY in
    /// Test mode and ONLY while TsujiPlan.calendarWritesEnabled is false, to prove Nudge refuses
    /// to edit it. It is NOT in TsujiPlan.actionUIDs and must never be added there.
    static let testInviteeUID = "tsuji-plan-01-20261027@noah.flouty.uk"

    // MARK: - Types

    enum Status: Equatable {
        case missing
        case duplicate(Int)
        case overdue(Int)    // days overdue
        case dueSoon(Int)    // 0...7 days away
        case later(Int)      // more than 7 days away
        case cleared
    }

    struct Item: Identifiable, Equatable {
        let id: String              // the UID
        let number: Int             // 1–13; 0 for test entries
        let title: String
        let start: Date?            // start of the due day (all-day event start)
        let end: Date?              // last day, only for multi-day events
        let notes: String
        let status: Status
        let isTestEntry: Bool
        let calendarNotUpdated: Bool    // cleared in Nudge, Calendar write still owed
        let dryRun: Bool                // cleared while saving to Calendar is switched off
        let reopenedWithoutBackup: Bool // reopened on a device that has no alarm backup

        var isOpen: Bool {
            switch status {
            case .overdue, .dueSoon, .later: return true
            default: return false
            }
        }
        var canClear: Bool {
            switch status {
            case .cleared, .duplicate: return false
            default: return true
            }
        }
    }

    /// Per-UID local record. Cache + backup only; the Calendar title decides.
    struct Record: Codable {
        enum Write: String, Codable { case none, done, pending, dryRun }
        struct Alarm: Codable, Hashable {
            var offset: Double?
            var date: Date?
        }
        var lastTitle: String = ""
        var lastDue: String?               // yyyy-MM-dd
        var cleared: Bool = false          // what this device believes
        var clearedOn: String?             // yyyy-MM-dd (local)
        var write: Write = .none           // state of the Calendar side of the clear
        var originalTitle: String?
        var alarmBackup: [Alarm]?          // only on the device that cleared it
        var restorePending: Bool = false   // undo seen, alarm/notes restore not saved yet
        var reopenedWithoutBackup: Bool = false
    }

    enum ClearResult {
        case cleared(String)
        case refused([String])
    }

    enum TsujiError: Error {
        case writesDisabled
        case refused([String])
    }

    struct PlannedNotification {
        let id: String
        let fire: Date
        let title: String
        let body: String
    }

    // MARK: - Published state

    @Published private(set) var items: [Item] = []
    @Published private(set) var problem: String?
    @Published private(set) var collapsed: Bool
    @Published private(set) var hasLoaded = false

    @Published var testMode: Bool {
        didSet { defaults.set(testMode, forKey: K.testMode); reload() }
    }
    @Published var fakeToday: Date {
        didSet { defaults.set(fakeToday, forKey: K.fakeToday); reload() }
    }
    @Published var testMissingEntry: Bool {
        didSet { defaults.set(testMissingEntry, forKey: K.testMissing); reload() }
    }
    @Published var testInviteeEntry: Bool {
        didSet { defaults.set(testInviteeEntry, forKey: K.testInvitee); reload() }
    }

    // MARK: - Private state

    private enum K {
        static let records = "tsuji.records.v1"
        static let calendarID = "tsuji.calendarID"
        static let collapsed = "tsuji.collapsed"
        static let collapsedNow = "tsuji.collapsedNow"
        static let testMode = "tsuji.testMode"
        static let fakeToday = "tsuji.fakeToday"
        static let testMissing = "tsuji.testMissing"
        static let testInvitee = "tsuji.testInvitee"
    }

    private let defaults = UserDefaults.standard
    private var store = EKEventStore()
    private var storeHasAccess: Bool
    private var storeObserver: NSObjectProtocol?
    private var reloadTask: Task<Void, Never>?
    private var records: [String: Record]
    private var calendarID: String?
    private var collapsedNow: Set<String>

    static let defaultFakeToday: Date =
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2027, month: 1, day: 3)) ?? Date()

    private init() {
        let d = UserDefaults.standard
        collapsed = d.bool(forKey: K.collapsed)
        collapsedNow = Set(d.stringArray(forKey: K.collapsedNow) ?? [])
        testMode = d.bool(forKey: K.testMode)
        fakeToday = (d.object(forKey: K.fakeToday) as? Date) ?? TsujiStore.defaultFakeToday
        testMissingEntry = d.bool(forKey: K.testMissing)
        testInviteeEntry = d.bool(forKey: K.testInvitee)
        calendarID = d.string(forKey: K.calendarID)
        if let data = d.data(forKey: K.records),
           let decoded = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
        storeHasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        observeStore()
    }

    // MARK: - Dates (calendar dates in the device's time zone — spec section 4)

    static var realToday: Date { Calendar.current.startOfDay(for: Date()) }

    /// "Today" for the banner, the plan list and notification wording. Test mode can pretend.
    var effectiveToday: Date {
        testMode ? Calendar.current.startOfDay(for: fakeToday) : Self.realToday
    }

    static func days(from a: Date, to b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ d: Date) -> String { dayFormatter.string(from: d) }
    static func parseDay(_ s: String) -> Date? { dayFormatter.date(from: s) }

    static func status(due: Date, today: Date) -> Status {
        let d = days(from: today, to: due)
        if d < 0 { return .overdue(-d) }
        if d <= 7 { return .dueSoon(d) }
        return .later(d)
    }

    /// "tsuji-plan-24-20261029@noah.flouty.uk" → "24-20261029" (used in notification ids).
    static func shortID(_ uid: String) -> String {
        let base = uid.split(separator: "@").first.map(String.init) ?? uid
        return base.hasPrefix("tsuji-plan-") ? String(base.dropFirst("tsuji-plan-".count)) : base
    }

    // MARK: - Banner sections (spec section 5)

    /// Missing (and duplicate-error) rows first, then Overdue (oldest first), then Due soon
    /// (soonest first).
    var nowItems: [Item] {
        let problems = items.filter { item in
            switch item.status {
            case .missing, .duplicate: return true
            default: return false
            }
        }
        let overdue = items.compactMap { item -> (Item, Int)? in
            if case .overdue(let n) = item.status { return (item, n) }
            return nil
        }.sorted { $0.1 > $1.1 }.map { $0.0 }
        let soon = items.compactMap { item -> (Item, Int)? in
            if case .dueSoon(let n) = item.status { return (item, n) }
            return nil
        }.sorted { $0.1 < $1.1 }.map { $0.0 }
        return problems + overdue + soon
    }

    /// The next 3 "Later" items, soonest first.
    var nextItems: [Item] {
        let later = items.compactMap { item -> (Item, Int)? in
            if case .later(let n) = item.status { return (item, n) }
            return nil
        }.sorted { $0.1 < $1.1 }.map { $0.0 }
        return Array(later.prefix(3))
    }

    var bannerVisible: Bool { problem != nil || !nowItems.isEmpty }

    /// Collapsing never clears anything. It stays collapsed until expanded, or until a new item
    /// enters "Now" (approved choice 2).
    func setCollapsed(_ value: Bool) {
        collapsed = value
        collapsedNow = value ? Set(nowItems.map { $0.id }) : []
        persistCollapse()
    }

    // MARK: - Reading (spec section 3)

    /// The UIDs shown: the 13, plus Test-mode entries only while saving to Calendar is off.
    private var displayUIDs: [String] {
        var uids = TsujiPlan.actionUIDs
        if testMode && !TsujiPlan.calendarWritesEnabled {
            if testMissingEntry { uids.append(Self.testMissingUID) }
            if testInviteeEntry { uids.append(Self.testInviteeUID) }
        }
        return uids
    }

    /// Re-read the calendar. Call on launch, on foreground, and (automatically) on
    /// EKEventStoreChanged.
    func reload() {
        reloadTask?.cancel()
        reloadTask = nil
        problem = nil

        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            problem = "Calendar access is off, so Nudge can't check your Tsuji plan. Turn on Full Access for Nudge in Settings → Privacy & Security → Calendars."
            items = []
            finish()
            return
        }
        if !storeHasAccess {
            // A store made before access was granted may see no calendars.
            store = EKEventStore()
            storeHasAccess = true
            observeStore()
        }
        guard let cal = tsujiCalendar() else {
            items = []
            finish()
            return
        }

        var byUID: [String: [EKEvent]] = [:]
        for e in fetchEvents(in: cal) {
            let ext: String? = e.calendarItemExternalIdentifier
            if let ext { byUID[ext, default: []].append(e) }
        }

        let today = effectiveToday
        let c = Calendar.current
        var out: [Item] = []
        for (index, uid) in displayUIDs.enumerated() {
            let isTest = !TsujiPlan.actionUIDs.contains(uid)
            let number = isTest ? 0 : index + 1
            let matches = byUID[uid] ?? []
            var rec = records[uid] ?? Record()

            if matches.count > 1 {
                // Spec: show an error row instead of guessing.
                out.append(Item(id: uid, number: number,
                                title: rec.lastTitle.isEmpty ? (matches.first?.title ?? "Tsuji item") : rec.lastTitle,
                                start: rec.lastDue.flatMap { Self.parseDay($0) }, end: nil, notes: "",
                                status: .duplicate(matches.count), isTestEntry: isTest,
                                calendarNotUpdated: false, dryRun: false, reopenedWithoutBackup: false))
                continue
            }

            if let e = matches.first {
                if !isTest { reconcile(event: e, calendar: cal, record: &rec) }
                let title = e.title ?? ""
                let start = c.startOfDay(for: e.startDate ?? Date())
                let endDay = c.startOfDay(for: e.endDate ?? start)
                if !isTest {
                    rec.lastTitle = title
                    rec.lastDue = Self.dayKey(start)
                }
                let cleared = TsujiPlan.isCompletedTitle(title) || (!isTest && rec.cleared)
                out.append(Item(id: uid, number: number, title: title, start: start,
                                end: endDay > start ? endDay : nil, notes: e.notes ?? "",
                                status: cleared ? .cleared : Self.status(due: start, today: today),
                                isTestEntry: isTest,
                                calendarNotUpdated: !isTest && rec.cleared && rec.write == .pending,
                                dryRun: !isTest && rec.cleared && rec.write == .dryRun,
                                reopenedWithoutBackup: !isTest && rec.reopenedWithoutBackup))
            } else {
                let title = rec.lastTitle.isEmpty
                    ? (isTest ? "Made-up test event" : "Unknown event (not seen on this device yet)")
                    : rec.lastTitle
                out.append(Item(id: uid, number: number, title: title,
                                start: rec.lastDue.flatMap { Self.parseDay($0) }, end: nil, notes: "",
                                status: (!isTest && rec.cleared) ? .cleared : .missing,
                                isTestEntry: isTest, calendarNotUpdated: false,
                                dryRun: !isTest && rec.cleared && rec.write == .dryRun,
                                reopenedWithoutBackup: false))
            }
            if !isTest { records[uid] = rec }
        }
        items = out
        finish()
    }

    /// Debounced reload for bursts of EKEventStoreChanged.
    func reloadSoon() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self.reload()
        }
    }

    private func finish() {
        hasLoaded = true
        saveRecords()
        // Re-expand a collapsed banner when a new item enters "Now".
        let nowIDs = Set(nowItems.map { $0.id })
        if collapsed && !nowIDs.isSubset(of: collapsedNow) {
            collapsed = false
            collapsedNow = []
            persistCollapse()
        }
        Task { await TsujiNotifications.schedule() }
    }

    private func observeStore() {
        if let o = storeObserver { NotificationCenter.default.removeObserver(o) }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { _ in
            Task { @MainActor in TsujiStore.shared.reloadSoon() }
        }
    }

    /// Find Tsuji Plan by its stored calendarIdentifier, falling back to the title. The
    /// identifier is per device (Test 0: different on iPhone and Mac), so it's stored locally.
    private func tsujiCalendar() -> EKCalendar? {
        if let id = calendarID, let c = store.calendar(withIdentifier: id) { return c }
        let named = store.calendars(for: .event).filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == TsujiPlan.calendarTitle
        }
        guard named.count == 1 else {
            problem = named.isEmpty
                ? "No calendar called “Tsuji Plan” was found on this device, so Nudge can't check your plan."
                : "There's more than one calendar called “Tsuji Plan”, so Nudge won't guess which one to use."
            return nil
        }
        calendarID = named[0].calendarIdentifier
        defaults.set(calendarID, forKey: K.calendarID)
        return named[0]
    }

    /// Today − 1 year, for 4 years minus a day (EventKit caps a search at four years).
    /// Always the REAL date, even in Test mode.
    private func fetchEvents(in cal: EKCalendar) -> [EKEvent] {
        let c = Calendar.current
        let today = Self.realToday
        let start = c.date(byAdding: .year, value: -1, to: today) ?? today
        let fourYears = c.date(byAdding: .year, value: 4, to: start) ?? today
        let end = c.date(byAdding: .day, value: -1, to: fourYears) ?? today
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [cal]))
    }

    // MARK: - Source of truth (spec section 7)

    private func reconcile(event e: EKEvent, calendar cal: EKCalendar, record rec: inout Record) {
        if TsujiPlan.isCompletedTitle(e.title ?? "") {
            // Calendar says cleared. If Nudge thought it was open (cleared in Calendar, on the
            // other device, or local data lost): treat it as cleared. Alarms are not touched.
            if !rec.cleared {
                rec.cleared = true
                rec.clearedOn = nil
                rec.reopenedWithoutBackup = false
            }
            rec.write = .done
            rec.restorePending = false
            return
        }

        if !rec.cleared {
            if rec.restorePending { applyRestore(event: e, calendar: cal, record: &rec) }
            return
        }

        // Nudge thinks it's cleared, but the Calendar title is open.
        switch rec.write {
        case .dryRun:
            // A dry-run clear must never become a real Calendar write. Once saving is switched
            // on, simply forget it.
            if TsujiPlan.calendarWritesEnabled { rec = Self.forgetClear(rec) }
        case .pending:
            // The earlier save failed (offline / permission). Try again.
            do {
                try writeClear(e, calendar: cal)
                rec.write = .done
            } catch {
                e.rollback()
            }
        case .done:
            // Noah removed the COMPLETED prefix in Calendar = undo.
            rec.cleared = false
            rec.write = .none
            rec.clearedOn = nil
            rec.reopenedWithoutBackup = (rec.alarmBackup ?? []).isEmpty
            rec.restorePending = true
            applyRestore(event: e, calendar: cal, record: &rec)
        case .none:
            // Cleared in Nudge only while the event was missing (approved choice 6). Stays
            // cleared in Nudge; nothing to write.
            break
        }
    }

    /// Undo: restore alarms from this device's backup (exact duplicates skipped — Noah,
    /// 1 Nov 2026) and add a "Reopened in Nudge on …" line, unless the other device already did.
    private func applyRestore(event e: EKEvent, calendar cal: EKCalendar, record rec: inout Record) {
        guard TsujiPlan.calendarWritesEnabled else {
            rec.restorePending = false
            return
        }
        var changed = false
        let present = Set((e.alarms ?? []).map { Self.alarmValue($0) })
        for value in Self.dedupe(rec.alarmBackup ?? []) where !present.contains(value) {
            if let alarm = Self.makeAlarm(value) {
                e.addAlarm(alarm)
                changed = true
            }
        }
        if !Self.lastNudgeLineIsReopened(e.notes) {
            e.notes = Self.appendLine(e.notes, "Reopened in Nudge on \(Self.dayKey(Self.realToday))")
            changed = true
        }
        guard changed else {
            rec.restorePending = false
            rec.alarmBackup = nil
            return
        }
        do {
            try saveToCalendar(e, calendar: cal)
            rec.restorePending = false
            rec.alarmBackup = nil
        } catch {
            e.rollback()   // stays pending; retried on the next reload
        }
    }

    // MARK: - Clearing (spec section 6)

    /// The only way to clear an item. The UI calls this after the phrase is typed; the phrase
    /// is checked again here.
    func clear(uid: String, typed: String) -> ClearResult {
        guard TsujiPlan.phraseMatches(typed) else {
            return .refused(["The phrase doesn't match. Type exactly: \(TsujiPlan.confirmPhrase)"])
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return .refused(["Calendar access is off, so Nudge can't check this event. Nothing was cleared."])
        }
        guard let cal = tsujiCalendar() else {
            return .refused([problem ?? "The Tsuji Plan calendar wasn't found. Nothing was cleared."])
        }
        let matches = fetchEvents(in: cal).filter { $0.calendarItemExternalIdentifier == uid }
        if matches.count > 1 {
            return .refused(["This event appears \(matches.count) times in Tsuji Plan, so Nudge won't guess which one to edit."])
        }
        let todayKey = Self.dayKey(Self.realToday)

        guard let e = matches.first else {
            // Missing from the calendar: clear in Nudge only, no Calendar edit (approved choice 6).
            guard TsujiPlan.actionUIDs.contains(uid) else {
                return .refused(["It isn't one of the 13 Tsuji action events."])
            }
            var rec = records[uid] ?? Record()
            rec.cleared = true
            rec.write = .none
            rec.clearedOn = todayKey
            records[uid] = rec
            reload()
            return .cleared("Cleared in Nudge. This event isn't in your calendar, so nothing in Calendar was changed.")
        }

        let failures = TsujiPlan.guardFailures(Self.guardInput(e, calendar: cal))
        guard failures.isEmpty else { return .refused(failures) }

        var rec = records[uid] ?? Record()
        rec.originalTitle = e.title
        rec.alarmBackup = Self.dedupe((e.alarms ?? []).map { Self.alarmValue($0) })
        rec.cleared = true
        rec.clearedOn = todayKey
        rec.restorePending = false
        rec.reopenedWithoutBackup = false

        let message: String
        if !TsujiPlan.calendarWritesEnabled {
            rec.write = .dryRun
            message = "Cleared in Nudge only. Saving to Calendar is switched off in this build, so your calendar wasn't changed."
        } else {
            do {
                try writeClear(e, calendar: cal)
                rec.write = .done
                message = "Cleared. In Calendar the title now starts with “COMPLETED”, and the event's alerts are off."
            } catch {
                e.rollback()
                rec.write = .pending
                message = "Cleared in Nudge, but Calendar wasn't updated yet. Nudge will try again next time it opens."
            }
        }
        records[uid] = rec
        reload()
        return .cleared(message)
    }

    /// Test mode: forget every clear made while saving to Calendar was switched off.
    func resetTestClears() {
        for (uid, rec) in records where rec.write == .dryRun {
            records[uid] = Self.forgetClear(rec)
        }
        reload()
    }

    private static func forgetClear(_ r: Record) -> Record {
        var r = r
        r.cleared = false
        r.write = .none
        r.clearedOn = nil
        r.originalTitle = nil
        r.alarmBackup = nil
        r.restorePending = false
        return r
    }

    // MARK: - Calendar writes (all gated)

    private func writeClear(_ e: EKEvent, calendar cal: EKCalendar) throws {
        try checkWritable(e, calendar: cal)   // before touching the event in memory
        let title = e.title ?? ""
        if !TsujiPlan.isCompletedTitle(title) { e.title = TsujiPlan.completedPrefix + title }
        e.notes = Self.appendLine(e.notes, "Completed in Nudge on \(Self.dayKey(Self.realToday))")
        for alarm in e.alarms ?? [] { e.removeAlarm(alarm) }
        try saveToCalendar(e, calendar: cal)
    }

    /// THE ONLY PLACE Tsuji code saves to Calendar. Re-checks the master switch and every
    /// guardrail on the event itself, then saves this one occurrence.
    private func saveToCalendar(_ e: EKEvent, calendar cal: EKCalendar) throws {
        try checkWritable(e, calendar: cal)
        try store.save(e, span: .thisEvent, commit: true)
    }

    private func checkWritable(_ e: EKEvent, calendar cal: EKCalendar) throws {
        guard TsujiPlan.calendarWritesEnabled else { throw TsujiError.writesDisabled }
        let f = TsujiPlan.guardFailures(Self.guardInput(e, calendar: cal))
        guard f.isEmpty else { throw TsujiError.refused(f) }
    }

    static func guardInput(_ e: EKEvent, calendar cal: EKCalendar) -> TsujiPlan.GuardInput {
        let ext: String? = e.calendarItemExternalIdentifier
        return TsujiPlan.GuardInput(
            uid: ext ?? "",
            inTsujiPlanCalendar: e.calendar?.calendarIdentifier == cal.calendarIdentifier,
            hasAttendees: e.hasAttendees,
            calendarEditable: e.calendar?.allowsContentModifications ?? false,
            repeats: e.hasRecurrenceRules)
    }

    // MARK: - Helpers

    private static func alarmValue(_ a: EKAlarm) -> Record.Alarm {
        if let d = a.absoluteDate { return Record.Alarm(offset: nil, date: d) }
        return Record.Alarm(offset: a.relativeOffset, date: nil)
    }

    private static func makeAlarm(_ v: Record.Alarm) -> EKAlarm? {
        if let d = v.date { return EKAlarm(absoluteDate: d) }
        if let o = v.offset { return EKAlarm(relativeOffset: o) }
        return nil
    }

    private static func dedupe(_ list: [Record.Alarm]) -> [Record.Alarm] {
        var seen = Set<Record.Alarm>()
        return list.filter { seen.insert($0).inserted }
    }

    static func appendLine(_ notes: String?, _ line: String) -> String {
        let existing = notes ?? ""
        if existing.isEmpty { return line }
        return existing.hasSuffix("\n") ? existing + line : existing + "\n" + line
    }

    /// True if the last "… in Nudge on …" line in the notes is a "Reopened" line, so a second
    /// device doesn't add another one.
    static func lastNudgeLineIsReopened(_ notes: String?) -> Bool {
        let lines = (notes ?? "").components(separatedBy: .newlines).filter { $0.contains(" in Nudge on ") }
        return lines.last?.hasPrefix("Reopened in Nudge on") ?? false
    }

    private func saveRecords() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: K.records) }
    }

    private func persistCollapse() {
        defaults.set(collapsed, forKey: K.collapsed)
        defaults.set(Array(collapsedNow), forKey: K.collapsedNow)
    }

    // MARK: - Notifications plan (spec section 8)

    /// 09:00 local on the due date, then every day at 09:00 until cleared, for the next
    /// `daysAhead` days. Soonest first, so trimming drops the furthest-out days first.
    /// In Test mode the pretend days are moved onto real days (pretend today → real today) and
    /// titled "[TEST]".
    func notificationPlan(daysAhead: Int) -> [PlannedNotification] {
        guard problem == nil else { return [] }
        let c = Calendar.current
        let pretendToday = effectiveToday
        let shift = Self.days(from: pretendToday, to: Self.realToday)
        let now = Date()
        var out: [PlannedNotification] = []
        for item in items where item.isOpen && !item.isTestEntry {
            guard let due = item.start else { continue }
            for k in 0..<daysAhead {
                guard let day = c.date(byAdding: .day, value: k, to: pretendToday), day >= due,
                      let realDay = c.date(byAdding: .day, value: shift, to: day),
                      let fire = c.date(bySettingHour: 9, minute: 0, second: 0, of: realDay),
                      fire > now else { continue }
                let late = Self.days(from: due, to: day)
                let when = late == 0 ? "due today" : "\(late) day\(late == 1 ? "" : "s") overdue"
                out.append(PlannedNotification(
                    id: "\(TsujiNotifications.prefix)\(Self.shortID(item.id))-\(Self.dayKey(day))",
                    fire: fire,
                    title: "\(testMode ? "[TEST] " : "")Tsuji: \(item.title) — \(when)",
                    body: "Clear it in Nudge when it's done."))
            }
        }
        return out.sorted { $0.fire < $1.fire }
    }

    // MARK: - Safety self-test (Test mode; fix 2 — made-up values only)

    static func selfTest() -> [String] {
        struct GuardCase { let name: String; let input: TsujiPlan.GuardInput; let expectAllowed: Bool }
        let real = TsujiPlan.actionUIDs[0]
        let cases: [GuardCase] = [
            GuardCase(name: "Real action event, normal",
                      input: TsujiPlan.GuardInput(uid: real, inTsujiPlanCalendar: true, hasAttendees: false, calendarEditable: true, repeats: false),
                      expectAllowed: true),
            GuardCase(name: "Action event with invitees",
                      input: TsujiPlan.GuardInput(uid: real, inTsujiPlanCalendar: true, hasAttendees: true, calendarEditable: true, repeats: false),
                      expectAllowed: false),
            GuardCase(name: "Open campus UID 01 (not one of the 13, has invitees)",
                      input: TsujiPlan.GuardInput(uid: testInviteeUID, inTsujiPlanCalendar: true, hasAttendees: true, calendarEditable: true, repeats: false),
                      expectAllowed: false),
            GuardCase(name: "Made-up UID",
                      input: TsujiPlan.GuardInput(uid: testMissingUID, inTsujiPlanCalendar: true, hasAttendees: false, calendarEditable: true, repeats: false),
                      expectAllowed: false),
            GuardCase(name: "Action event in another calendar",
                      input: TsujiPlan.GuardInput(uid: real, inTsujiPlanCalendar: false, hasAttendees: false, calendarEditable: true, repeats: false),
                      expectAllowed: false),
            GuardCase(name: "Read-only calendar",
                      input: TsujiPlan.GuardInput(uid: real, inTsujiPlanCalendar: true, hasAttendees: false, calendarEditable: false, repeats: false),
                      expectAllowed: false),
            GuardCase(name: "Repeating event",
                      input: TsujiPlan.GuardInput(uid: real, inTsujiPlanCalendar: true, hasAttendees: false, calendarEditable: true, repeats: true),
                      expectAllowed: false),
        ]
        let phrases: [(String, Bool)] = [
            ("Confirmed and completed", true),
            ("  Confirmed and completed  ", true),
            ("confirmed and completed", false),
            ("Confirmed", false),
            ("", false),
            ("Confirmed and completed.", false),
        ]
        var lines: [String] = []
        var allOK = true
        for c in cases {
            let allowed = TsujiPlan.guardFailures(c.input).isEmpty
            let ok = allowed == c.expectAllowed
            allOK = allOK && ok
            lines.append("\(ok ? "PASS" : "FAIL")  \(c.name): \(allowed ? "allowed" : "refused")")
        }
        for (typed, expect) in phrases {
            let matches = TsujiPlan.phraseMatches(typed)
            let ok = matches == expect
            allOK = allOK && ok
            lines.append("\(ok ? "PASS" : "FAIL")  Phrase \"\(typed)\": \(matches ? "accepted" : "rejected")")
        }
        lines.append("INFO  Saving to Calendar is \(TsujiPlan.calendarWritesEnabled ? "ON" : "OFF") in this build")
        return [allOK ? "ALL CHECKS PASSED" : "SOMETHING FAILED — tell Claude"] + lines
    }
}
