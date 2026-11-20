// BreakfastReminders.swift — Nudge (iOS + Mac Catalyst)
//
// Breakfast BUY reminders (Noah, 20 Nov 2026 — revised the same day). From the Breakfast sheet
// Noah sets a date + time to buy either "everything unbought" or picked items with a count
// each, once or every week. Each one is a normal Nudge reminder in the "Breakfast" list,
// carrying a `BreakfastPlan`, so notifications, snooze, reschedule and sync work as usual.
//
// RULES (Noah's choices)
//   • A reminder can NEVER tick anything. Items are only ticked in the shopping list (or
//     Budget). toggleComplete refuses to complete a Breakfast reminder by hand — every path
//     (cards, Next up, menus, Siri, notifications) goes through it — and opens the shopping
//     list instead, with that reminder's items grouped at the top.
//   • It completes itself only when everything it covers is bought or skipped
//     (`syncBreakfastReminders`, with `breakfastAutoCompleting` set). Partly bought → it stays,
//     and its title and notes drop to what's left.
//   • "Everything unbought" = the items unbought WHEN IT WAS SET (a snapshot in `plan.items`).
//     A weekly one takes a fresh snapshot each week (items reset to nil on each new week).
//   • Titles and notifications never name the shop.
//   • No exact duplicates for the same week; an overlap only warns.
//   • Always listed first on Today, Overdue, Upcoming (and the widget, step 2).
//   • Past midnight on its day and still not done → banner: Reschedule / Delete
//     (weekly: Delete this week / Stop weekly).

import Foundation

extension Reminder {
    var isBreakfast: Bool { breakfast != nil }
}

extension NudgeStore {
    static let breakfastListId = "breakfast"

    // MARK: - Create

    /// Add a Breakfast buy reminder. Creates the "Breakfast" list the first time.
    /// The caller checks duplicates first (`breakfastDuplicate`).
    func addBreakfastReminder(plan: BreakfastPlan, due: Date, weekly: Bool) {
        ensureBreakfastList()
        let id = "r" + String(UUID().uuidString.prefix(12))
        let week = Self.breakfastWeek(of: iso(due))
        var plan = plan
        plan.ticked = nil
        if plan.mode == "all", plan.items == nil { plan.items = Self.breakfastSnapshot(week: week) }
        let text = Self.breakfastText(plan, week: week)
        saveReminder(editing: nil, title: text.title, notes: text.notes ?? "",
                     hasDue: true, due: due, hasTime: true,
                     listId: Self.breakfastListId, priority: "normal",
                     recurrence: weekly ? Recurrence(freq: "weekly", interval: 1, until: nil) : nil,
                     idForNew: id)
        if let i = reminders.firstIndex(where: { $0.id == id }) {
            reminders[i].breakfast = plan
            reminders[i].source = "breakfast"
            persist()
        }
    }

    private func ensureBreakfastList() {
        guard !lists.contains(where: { $0.id == Self.breakfastListId }) else { return }
        lists.append(ReminderList(id: Self.breakfastListId, name: "Breakfast", color: "#D9A441",
                                  builtin: nil, special: nil, linked: nil, updatedAt: iso(Date())))
    }

    /// "Everything unbought" snapshot: open units per item in that week. nil if the week
    /// isn't published yet (taken later, on the first refresh that has it).
    static func breakfastSnapshot(week: String) -> [BreakfastPlanItem]? {
        let bs = BreakfastStore.shared
        guard bs.hasWeek(week) else { return nil }
        var order: [String] = []
        var count: [String: Int] = [:]
        var name: [String: String] = [:]
        for r in bs.openRows(week: week) {
            if count[r.item_id] == nil { order.append(r.item_id) }
            count[r.item_id, default: 0] += 1
            name[r.item_id] = r.name
        }
        return order.map { BreakfastPlanItem(itemId: $0, name: name[$0] ?? "", count: count[$0] ?? 0) }
    }

    // MARK: - Duplicates

    /// Plan in a comparable form: "all" or the sorted "itemId×count" list.
    private static func signature(_ p: BreakfastPlan) -> String {
        if p.mode == "all" { return "all" }
        return (p.items ?? []).filter { $0.count > 0 }.map { "\($0.itemId)×\($0.count)" }.sorted().joined(separator: ",")
    }

    /// An open Breakfast reminder for the same week covering exactly the same thing.
    func breakfastDuplicate(_ plan: BreakfastPlan, due: Date) -> Reminder? {
        let week = Self.breakfastWeek(of: iso(due))
        let sig = Self.signature(plan)
        return reminders.first { r in
            guard let p = r.breakfast, !r.isCompleted else { return false }
            return Self.breakfastWeek(of: r.dueDate) == week && Self.signature(p) == sig
        }
    }

    /// Other open Breakfast reminders that week sharing at least one item (warning only).
    func breakfastOverlaps(_ plan: BreakfastPlan, due: Date) -> [Reminder] {
        let week = Self.breakfastWeek(of: iso(due))
        let mine = Set((plan.mode == "all" ? (Self.breakfastSnapshot(week: week) ?? []) : (plan.items ?? []))
            .filter { $0.count > 0 }.map(\.itemId))
        return reminders.filter { r in
            guard let p = r.breakfast, !r.isCompleted, Self.breakfastWeek(of: r.dueDate) == week else { return false }
            if plan.mode == "all" || p.mode == "all" && p.items == nil { return true }
            return !mine.isDisjoint(with: (p.items ?? []).filter { $0.count > 0 }.map(\.itemId))
        }
    }

    // MARK: - Keep titles current, complete when nothing is left

    /// Run after every Breakfast refresh and every tick in the shopping list. Only touches
    /// reminders whose week Budget has published, so an empty / offline list never completes
    /// or renames anything.
    func syncBreakfastReminders() {
        let bs = BreakfastStore.shared
        guard bs.state == .ok else { return }
        var changed = false
        var toComplete: [Reminder] = []
        for i in reminders.indices {
            guard let plan = reminders[i].breakfast, !reminders[i].isCompleted else { continue }
            let week = Self.breakfastWeek(of: reminders[i].dueDate)
            guard bs.hasWeek(week) else { continue }
            // Weekly "everything": take this week's snapshot the first time the week is here.
            if plan.mode == "all", plan.items == nil {
                reminders[i].breakfast?.items = Self.breakfastSnapshot(week: week)
                changed = true
            }
            let p = reminders[i].breakfast ?? plan
            if Self.breakfastLeft(p, week: week).isEmpty {
                toComplete.append(reminders[i])
                continue
            }
            let text = Self.breakfastText(p, week: week)
            let notes = text.notes ?? ""
            if reminders[i].title != text.title || (reminders[i].notes ?? "") != notes {
                reminders[i].title = text.title
                reminders[i].notes = notes
                reminders[i].updatedAt = iso(Date())
                changed = true
            }
        }
        if changed { persist() }
        // Everything bought/skipped → complete it. The only way a Breakfast reminder completes.
        guard !toComplete.isEmpty else { return }
        breakfastAutoCompleting = true
        for r in toComplete { toggleComplete(r) }
        breakfastAutoCompleting = false
    }

    // MARK: - What's left

    /// What's still to buy: (display name, units) per item, in plan order, zero-free.
    /// Each item counts min(planned, still open that week) — so it drops as you buy.
    static func breakfastLeft(_ plan: BreakfastPlan, week: String) -> [(name: String, count: Int)] {
        let open = BreakfastStore.shared.openRows(week: week)
        var count: [String: Int] = [:]
        var name: [String: String] = [:]
        for r in open { count[r.item_id, default: 0] += 1; name[r.item_id] = r.name }
        if plan.mode == "all", plan.items == nil {   // snapshot not taken yet: everything open
            var order: [String] = []
            for r in open where !order.contains(r.item_id) { order.append(r.item_id) }
            return order.map { (name: shortName(name[$0] ?? ""), count: count[$0] ?? 0) }
        }
        return (plan.items ?? []).compactMap { it -> (name: String, count: Int)? in
            let n = min(it.count, count[it.itemId] ?? 0)
            return n > 0 ? (name: shortName(name[it.itemId] ?? it.name), count: n) : nil
        }
    }

    /// The open rows a reminder covers (its group at the top of the shopping list).
    static func breakfastRows(for r: Reminder) -> [BreakfastRow] {
        guard let plan = r.breakfast else { return [] }
        let week = breakfastWeek(of: r.dueDate)
        let open = BreakfastStore.shared.openRows(week: week)
        if plan.mode == "all", plan.items == nil { return open }
        return (plan.items ?? []).flatMap { it in open.filter { $0.item_id == it.itemId }.prefix(max(0, it.count)) }
    }

    /// Title and notes. No shop names (Noah, 20 Nov 2026).
    ///   one item     → "Buy: Single Lemon ×2"          (no "×1")
    ///   several      → "Breakfast: Single Lemon ×2 · Bananas"
    ///   everything   → "Breakfast: 6 things to buy", notes "Single Lemon ×3 · …"
    static func breakfastText(_ plan: BreakfastPlan, week: String) -> (title: String, notes: String?) {
        var left = breakfastLeft(plan, week: week)
        if left.isEmpty {   // week not loaded yet: fall back to the plan itself
            left = (plan.items ?? []).filter { $0.count > 0 }.map { (name: shortName($0.name), count: $0.count) }
        }
        func part(_ e: (name: String, count: Int)) -> String { e.count > 1 ? "\(e.name) ×\(e.count)" : e.name }
        if plan.mode == "all" {
            let total = left.reduce(0) { $0 + $1.count }
            let title = total > 0 ? "Breakfast: \(total) thing\(total == 1 ? "" : "s") to buy" : "Breakfast shopping"
            return (title, left.isEmpty ? nil : left.map(part).joined(separator: " · "))
        }
        if left.count == 1 { return ("Buy: " + part(left[0]), nil) }
        if left.isEmpty { return ("Breakfast shopping", nil) }
        return ("Breakfast: " + left.map(part).joined(separator: " · "), nil)
    }

    /// "Beef-Pork Mix Meat | 450G" → "Beef-Pork Mix Meat" (the size part only adds length).
    static func shortName(_ n: String) -> String {
        let base = n.components(separatedBy: " | ").first ?? n
        let t = base.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? n : t
    }

    // MARK: - Overdue (past midnight) and ordering

    /// Open Breakfast reminders whose due DAY has passed (not just its time today).
    func breakfastOverdue() -> [Reminder] {
        let today = Calendar.current.startOfDay(for: Date())
        return reminders.filter { r in
            guard r.isBreakfast, !r.isCompleted, let d = parseDate(r.dueDate) else { return false }
            return Calendar.current.startOfDay(for: d) < today
        }.sorted { (parseDate($0.dueDate) ?? .distantPast) < (parseDate($1.dueDate) ?? .distantPast) }
    }

    /// Breakfast reminders first, everything else in its existing order (stable).
    static func breakfastFirst(_ items: [Reminder]) -> [Reminder] {
        items.filter(\.isBreakfast) + items.filter { !$0.isBreakfast }
    }

    /// "Sat 21 Nov, 10:00" — used for the group title and the banner.
    static func breakfastWhen(_ r: Reminder) -> String {
        guard let d = parseDate(r.dueDate) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: d)
    }

    /// The Monday ("YYYY-MM-DD", device time zone) of the week containing an ISO due date.
    static func breakfastWeek(of due: String?) -> String {
        let d = parseDate(due) ?? Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let weekday = cal.component(.weekday, from: d)          // 1 = Sunday … 7 = Saturday
        let back = (weekday + 5) % 7                            // days since Monday
        let monday = cal.date(byAdding: .day, value: -back, to: d) ?? d
        return BreakfastStore.dayKey(monday)
    }
}
