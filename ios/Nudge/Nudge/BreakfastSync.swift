// BreakfastSync.swift — Nudge (iOS + Mac Catalyst)
//
// Breakfast shopping list shared with the Budget app (decided with Noah 2026-11-19).
// Spec: handoffs/HANDOFF_2026-11-19_breakfast-nudge-sync.md (sections 5, 6 "Nudge side", 11).
//
// WHAT THIS TALKS TO
//   Only the `breakfast_list` table in the BUDGET app's Supabase project, with Budget's
//   public-tier publishable key (Secrets.budgetSupabaseURL / budgetPublishableKey, in the
//   gitignored Secrets.swift). The key goes in the `apikey` header ONLY — exactly as Budget
//   sends it. Nudge's own sign-in token (Auth.bearer) is NEVER sent to Budget's project,
//   and nothing here ever touches Budget's `finance_data` table.
//
// WHAT NUDGE MAY DO
//   • Read rows (Budget creates, renames, reprices and deletes them — Nudge never does).
//   • Flip one row's status between "open" and "done", sending ONLY
//     status, done_on, changed_by = "nudge", updated_at.
//   • Never "skipped": skips change Budget's money, so they happen in Budget (Skip button
//     only explains this and offers the budget:// link). Skipped rows are hidden.
//
// NEWEST WINS, ENFORCED BY THE SERVER
//   Every PATCH carries `status=neq.skipped&updated_at=lt.<our stamp>`, so a tick is applied
//   only if the row isn't skipped and nobody wrote it after us. Our stamp is
//   syncStamp(after: the row's stamp we saw) — strictly newer than the row as we saw it, even
//   if this device's clock runs slightly behind Budget's. That matters twice: the PATCH isn't
//   wrongly refused, and Budget (which applies a Nudge row only when its updated_at is newer
//   than what Budget last wrote) doesn't ignore it.
//
// OFFLINE
//   A tick is shown at once and kept in a small saved queue (one entry per row, latest tap
//   wins) until the PATCH gets a reply. The last fetched list is saved for offline viewing.

import Foundation
import Combine

/// One row of `breakfast_list` (same columns as Budget's Calc.BreakfastListRow).
struct BreakfastRow: Codable, Identifiable, Equatable {
    let id: String          // "<Monday>|<item_id>|<unit>"
    let week: String        // Monday "YYYY-MM-DD"
    let pay_month: String
    let item_id: String
    let unit: Int           // 0 = item has no units; else 1…unit_of
    let unit_of: Int
    let size: Double        // 1, or e.g. 0.5 for a half last unit
    let name: String
    let shop: String
    let price: Double
    let sort: Int
    var status: String      // "open" | "done" | "skipped"
    var done_on: String?
    var changed_by: String
    var updated_at: String

    var isDone: Bool { status == "done" }
    var isSkipped: Bool { status == "skipped" }
}

/// A tick or untick waiting to reach the server.
struct BreakfastPendingTick: Codable, Equatable {
    let id: String
    let done: Bool
    let doneOn: String?
    let stamp: String
}

/// One week as Nudge shows it.
struct BreakfastWeek: Identifiable, Equatable {
    let monday: String
    let rows: [BreakfastRow]       // skipped rows already removed, in Budget's order
    var id: String { monday }
    var doneCount: Int { rows.filter(\.isDone).count }
}

@MainActor
final class BreakfastStore: ObservableObject {
    static let shared = BreakfastStore()

    enum LoadState: Equatable {
        case never        // nothing fetched yet on this device
        case ok
        case offline      // last fetch failed (no network / server error) — showing the saved copy
        case notSetUp     // the table doesn't exist in Budget's project yet
    }

    /// The rows as last fetched, with any not-yet-sent ticks applied on top.
    @Published private(set) var rows: [BreakfastRow] = []
    @Published private(set) var state: LoadState = .never
    @Published private(set) var lastFetched: Date?

    private var pending: [String: BreakfastPendingTick] = [:]
    private var fetching = false
    private var flushing = false
    private var flushAgain = false

    private static let rowsKey = "breakfast.rows.v1"
    private static let pendingKey = "breakfast.pending.v1"
    private static let fetchedKey = "breakfast.fetchedAt.v1"
    private static let table = "breakfast_list"

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.rowsKey),
           let saved = try? JSONDecoder().decode([BreakfastRow].self, from: data) { rows = saved }
        if let data = d.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([String: BreakfastPendingTick].self, from: data) { pending = saved }
        if let t = d.object(forKey: Self.fetchedKey) as? Date { lastFetched = t; state = .offline }
        applyPending()
    }

    // MARK: - What the screens show

    /// This week and next week (the first two weeks whose Sunday is today or later), with
    /// skipped rows hidden. Budget decides the weeks; Nudge only reads them from the rows.
    var weeks: [BreakfastWeek] {
        let today = Self.dayKey()
        let live = rows.filter { !$0.isSkipped && Self.dayKey($0.week, adding: 6).map { $0 >= today } == true }
        let mondays = Array(Set(live.map(\.week))).sorted().prefix(2)
        return mondays.map { m in
            BreakfastWeek(monday: m, rows: live.filter { $0.week == m }
                .sorted { ($0.sort, $0.unit, $0.id) < ($1.sort, $1.unit, $1.id) })
        }
    }

    /// The week containing today, if Budget has published it.
    var thisWeek: BreakfastWeek? {
        let today = Self.dayKey()
        return weeks.first { $0.monday <= today }
    }

    // MARK: - Refresh

    /// Send queued ticks, then re-read both weeks. Safe to call often (open, 15 s poll,
    /// coming to the front, pull-to-refresh); overlapping calls are dropped.
    func refresh() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        await flushPending()

        // Weeks whose Sunday is today or later ⇔ Monday on or after (today − 6 days).
        let from = Self.dayKey(Self.dayKey(), adding: -6) ?? Self.dayKey()
        let path = "\(Self.table)?select=*&week=gte.\(Self.enc(from))&order=week.asc,sort.asc,unit.asc&limit=1000"
        guard var req = request(path, method: "GET") else { state = .offline; return }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                // PostgREST answers 404 (PGRST205) for a table that doesn't exist.
                state = (code == 404) ? .notSetUp : .offline
                return
            }
            let fetched = try JSONDecoder().decode([BreakfastRow].self, from: data)
            setRows(fetched)
            applyPending()
            lastFetched = Date()
            state = .ok
            saveRows()
            UserDefaults.standard.set(lastFetched, forKey: Self.fetchedKey)
        } catch {
            state = .offline
        }
    }

    // MARK: - Tick / untick

    /// Flip one row open ↔ done. Shows at once; the PATCH is queued and sent straight away.
    func toggle(_ row: BreakfastRow) {
        guard let cur = rows.first(where: { $0.id == row.id }) else { return }
        setDone(cur.id, !cur.isDone)
    }

    /// Set one row done (bought today) or open. No-op for skipped / unknown rows or when it
    /// is already in that state.
    func setDone(_ id: String, _ done: Bool) {
        guard let i = rows.firstIndex(where: { $0.id == id }), !rows[i].isSkipped, rows[i].isDone != done else { return }
        // Strictly newer than the row as we last saw it (see header: clock skew).
        let stamp = syncStamp(after: rows[i].updated_at)
        pending[id] = BreakfastPendingTick(id: id, done: done, doneOn: done ? Self.dayKey() : nil, stamp: stamp)
        savePending()
        applyPending()
        Task { await flushPending() }
    }

    // MARK: - Buy reminders (BreakfastReminders.swift)

    /// True once Budget has published rows for that week (any status).
    func hasWeek(_ monday: String) -> Bool { rows.contains { $0.week == monday } }

    /// Open (unbought, not skipped) rows of one week, in Budget's order.
    func openRows(week monday: String) -> [BreakfastRow] {
        rows.filter { $0.week == monday && !$0.isSkipped && !$0.isDone }
            .sorted { ($0.sort, $0.unit, $0.id) < ($1.sort, $1.unit, $1.id) }
    }

    /// Send queued ticks now (used by the notification Bought button, which may run with the
    /// app in the background and be suspended soon after).
    func flushNow() async { await flushPending() }

    /// Number of ticks not yet confirmed by the server.
    var pendingCount: Int { pending.count }

    // MARK: - Sending

    private func flushPending() async {
        if flushing { flushAgain = true; return }
        flushing = true
        defer { flushing = false }
        repeat {
            flushAgain = false
            for tick in pending.values.sorted(by: { $0.stamp < $1.stamp }) {
                let result = await patch(tick)
                switch result {
                case .sent(let serverRow):
                    // Only clear the queue entry if no newer tap replaced it meanwhile.
                    if pending[tick.id] == tick { pending[tick.id] = nil }
                    if let r = serverRow, let i = rows.firstIndex(where: { $0.id == r.id }) { rows[i] = r }
                case .refused:
                    // Row skipped in Budget, deleted, or changed after our tap: Budget's
                    // version stands. The next fetch redraws from the table.
                    if pending[tick.id] == tick { pending[tick.id] = nil }
                case .tryLater:
                    break   // offline / server trouble — keep it for the next refresh
                }
            }
            savePending()
            applyPending()
        } while flushAgain
    }

    private enum PatchResult { case sent(BreakfastRow?), refused, tryLater }

    private func patch(_ t: BreakfastPendingTick) async -> PatchResult {
        let path = "\(Self.table)?id=eq.\(Self.enc(t.id))&status=neq.skipped&updated_at=lt.\(Self.enc(t.stamp))"
        guard var req = request(path, method: "PATCH") else { return .refused }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=representation", forHTTPHeaderField: "Prefer")
        // ONLY these four fields. Name, price, shop, size and week are Budget's.
        var body: [String: Any] = ["status": t.done ? "done" : "open",
                                   "changed_by": "nudge",
                                   "updated_at": t.stamp]
        body["done_on"] = t.doneOn ?? NSNull()
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return .refused }
        req.httpBody = json
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                let changed = (try? JSONDecoder().decode([BreakfastRow].self, from: data)) ?? []
                return changed.isEmpty ? .refused : .sent(changed.first)
            }
            if code == 408 || code == 429 || code >= 500 || code == 0 { return .tryLater }
            return .refused   // other 4xx: malformed or table missing — retrying won't help
        } catch {
            return .tryLater
        }
    }

    // MARK: - Local state

    private func setRows(_ new: [BreakfastRow]) {
        if new != rows { rows = new }
    }

    /// Show queued ticks on top of the fetched rows. A queued tick on a row that is now
    /// skipped or gone simply has nothing to show on.
    private func applyPending() {
        guard !pending.isEmpty else { return }
        var out = rows
        for (id, t) in pending {
            guard let i = out.firstIndex(where: { $0.id == id }), !out[i].isSkipped else { continue }
            out[i].status = t.done ? "done" : "open"
            out[i].done_on = t.doneOn
        }
        setRows(out)
    }

    private func saveRows() {
        if let d = try? JSONEncoder().encode(rows) { UserDefaults.standard.set(d, forKey: Self.rowsKey) }
    }
    private func savePending() {
        if let d = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(d, forKey: Self.pendingKey) }
    }

    // MARK: - Request

    /// Budget's project, Budget's publishable key in `apikey` only — never Authorization,
    /// never Nudge's own session.
    private func request(_ pathAndQuery: String, method: String) -> URLRequest? {
        guard let u = URL(string: "\(Secrets.budgetSupabaseURL)/rest/v1/\(pathAndQuery)") else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue(Secrets.budgetPublishableKey, forHTTPHeaderField: "apikey")
        return r
    }

    /// Percent-encode one query value (ids contain "|", stamps contain ":").
    private static func enc(_ s: String) -> String {
        var ok = CharacterSet.alphanumerics
        ok.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: ok) ?? s
    }

    // MARK: - Day keys ("YYYY-MM-DD", device time zone — the same rule Budget uses)

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ d: Date = Date()) -> String {
        dayFormatter.timeZone = .current
        return dayFormatter.string(from: d)
    }
    static func date(_ key: String) -> Date? {
        dayFormatter.timeZone = .current
        return dayFormatter.date(from: key)
    }
    static func dayKey(_ key: String, adding days: Int) -> String? {
        guard let d = date(key),
              let n = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: d) else { return nil }
        return dayKey(n)
    }
    /// A strict "YYYY-MM-DD" that is a real date (used before putting a week into a link).
    static func isDayKey(_ s: String) -> Bool {
        s.count == 10 && s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
            && date(s).map { dayKey($0) == s } == true
    }
}
