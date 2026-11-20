// BreakfastReminders.swift — Nudge (iOS + Mac Catalyst)
//
// Breakfast BUY reminders (decided with Noah 2026-11-20). From the Breakfast sheet Noah sets a
// date + time to buy either "everything still unbought that week" or picked items with a
// count each, once or every week. Each one is a NORMAL Nudge reminder in the "Breakfast" list,
// carrying a `BreakfastPlan`, so notifications, snooze, cross-device sync and the Today widget
// all work as for any reminder.
//
// RULES (Noah's choices)
//   • Titles and notifications never name the shop.
//   • The reminder's week = the Mon–Sun week containing its due date.
//   • Completing it — in a list, the notification's "Bought" button — ticks what it covers
//     (BreakfastStore.markBought) and remembers exactly which rows (`plan.ticked`). Unticking
//     it unticks those rows again. Only the device that completes it ticks anything, so the
//     other device pulling the completed reminder can never tick a second time.
//   • It completes itself once nothing it covers is left to buy (bought or skipped).
//   • Its title (and, for "everything", the notes) follow what's left: "Buy: Single Lemon ×2".
//   • Weekly ones roll on to next week through the normal repeat machinery.

import Foundation

extension NudgeStore {
    static let breakfastListId = "breakfast"

    // MARK: - Create

    /// Add a Breakfast buy reminder. Creates the "Breakfast" list the first time.
    func addBreakfastReminder(plan: BreakfastPlan, due: Date, weekly: Bool) {
        ensureBreakfastList()
        let id = "r" + String(UUID().uuidString.prefix(12))
        let week = Self.breakfastWeek(of: iso(due))
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

    // MARK: - Complete / untick hook (called from toggleComplete)

    /// Apply a Breakfast reminder's tick or untick to the shared list. Called by toggleComplete
    /// on THIS device only — never on a pull — so a completion is applied exactly once.
    func applyBreakfastCompletion(at i: Int, nowComplete: Bool) {
        guard let plan = reminders[i].breakfast else { return }
        let bs = BreakfastStore.shared
        if nowComplete {
            let week = Self.breakfastWeek(of: reminders[i].dueDate)
            reminders[i].breakfast?.ticked = bs.markBought(plan, week: week)
        } else {
            bs.unmarkBought(plan.ticked ?? [])
            reminders[i].breakfast?.ticked = nil
        }
    }

    // MARK: - Keep titles current, complete when nothing is left

    /// Run after each Breakfast refresh. Only looks at weeks Budget has published, so an
    /// empty or offline list never completes or renames anything.
    func syncBreakfastReminders() {
        let bs = BreakfastStore.shared
        guard bs.state == .ok else { return }
        var changed = false
        var toComplete: [Reminder] = []
        for i in reminders.indices {
            guard let plan = reminders[i].breakfast, !reminders[i].isCompleted else { continue }
            let week = Self.breakfastWeek(of: reminders[i].dueDate)
            guard bs.hasWeek(week) else { continue }
            if Self.breakfastLeft(plan, week: week).isEmpty {
                toComplete.append(reminders[i])
                continue
            }
            let text = Self.breakfastText(plan, week: week)
            let notes = text.notes ?? ""
            if reminders[i].title != text.title || (reminders[i].notes ?? "") != notes {
                reminders[i].title = text.title
                reminders[i].notes = notes
                reminders[i].updatedAt = iso(Date())
                changed = true
            }
        }
        if changed { persist() }
        // Nothing left to buy → complete it (ticks nothing; a weekly one rolls on to next week).
        for r in toComplete { toggleComplete(r) }
    }

    // MARK: - Text

    /// What's still to buy: (display name, units) per item, in Budget's order, zero-free.
    static func breakfastLeft(_ plan: BreakfastPlan, week: String) -> [(name: String, count: Int)] {
        let open = BreakfastStore.shared.openRows(week: week)
        var order: [String] = []
        var count: [String: Int] = [:]
        var name: [String: String] = [:]
        for r in open {
            if count[r.item_id] == nil { order.append(r.item_id) }
            count[r.item_id, default: 0] += 1
            name[r.item_id] = r.name
        }
        if plan.mode == "all" {
            return order.map { (name: shortName(name[$0] ?? ""), count: count[$0] ?? 0) }
        }
        return (plan.items ?? []).compactMap { it -> (name: String, count: Int)? in
            let n = min(it.count, count[it.itemId] ?? 0)
            return n > 0 ? (name: shortName(name[it.itemId] ?? it.name), count: n) : nil
        }
    }

    /// Title and notes for a buy reminder. No shop names (Noah, 20 Nov 2026).
    ///   one item     → "Buy: Single Lemon ×2"          (no "×1")
    ///   several      → "Breakfast: Single Lemon ×2 · Bananas"
    ///   everything   → "Breakfast: 6 things to buy", notes "Single Lemon ×3 · …"
    static func breakfastText(_ plan: BreakfastPlan, week: String) -> (title: String, notes: String?) {
        var left = breakfastLeft(plan, week: week)
        if left.isEmpty, plan.mode != "all" {   // week not loaded yet: fall back to the plan itself
            left = (plan.items ?? []).filter { $0.count > 0 }.map { (name: shortName($0.name), count: $0.count) }
        }
        func part(_ e: (name: String, count: Int)) -> String { e.count > 1 ? "\(e.name) ×\(e.count)" : e.name }
        if plan.mode == "all" {
            let total = left.reduce(0) { $0 + $1.count }
            let title = total > 0 ? "Breakfast: \(total) thing\(total == 1 ? "" : "s") to buy" : "Breakfast shopping"
            return (title, left.isEmpty ? nil : left.map(part).joined(separator: " · "))
        }
        if left.count == 1 { return ("Buy: " + part(left[0]), nil) }
        return ("Breakfast: " + left.map(part).joined(separator: " · "), nil)
    }

    /// "Beef-Pork Mix Meat | 450G" → "Beef-Pork Mix Meat" (the size part only adds length).
    static func shortName(_ n: String) -> String {
        let base = n.components(separatedBy: " | ").first ?? n
        let t = base.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? n : t
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
