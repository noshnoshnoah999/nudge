// SmartScheduler.swift — Nudge (iOS)
// Intelligently spreads overdue reminders across the coming week so the pile
// clears itself instead of rotting. Weekends carry more (more free time),
// high-priority + oldest land soonest, and times land in the day's free window
// (weekday evenings / weekend daytime), staggered.

import Foundation

struct RescheduleChange: Identifiable, Codable {
    let id: String          // reminder id
    let title: String
    let oldDue: String?
    let newDue: String
    let newDate: Date
}

struct RescheduleResult: Identifiable {
    let id = UUID()
    let changes: [RescheduleChange]
    var auto: Bool
}

/// One persisted reschedule run — for the history page.
struct RescheduleLogEntry: Identifiable, Codable {
    let id: String
    let date: Date          // when the run happened
    let auto: Bool
    let changes: [RescheduleChange]
}

/// Persistent log of every Smart Reschedule run (local file, newest first).
enum RescheduleLog {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reschedule_log.json")
    }
    static func all() -> [RescheduleLogEntry] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RescheduleLogEntry].self, from: d)) ?? []
    }
    static func add(_ entry: RescheduleLogEntry) {
        var list = all()
        list.insert(entry, at: 0)
        if list.count > 200 { list = Array(list.prefix(200)) }
        if let d = try? JSONEncoder().encode(list) { try? d.write(to: url) }
    }
    static func clear() { try? FileManager.default.removeItem(at: url) }

    /// How many times each reminder id has been rescheduled (across all runs).
    static func counts() -> [String: Int] {
        var c: [String: Int] = [:]
        for e in all() { for ch in e.changes { c[ch.id, default: 0] += 1 } }
        return c
    }
}

enum SmartScheduler {
    // Free-time windows (24h decimal). Weekdays = evenings; weekends = daytime.
    private static let weekdayWindow = (start: 17.0, end: 21.5)
    private static let weekendWindow = (start: 10.0, end: 20.0)

    /// A smart slot for ONE reminder: tomorrow, in that day's free window
    /// (weekday evening / weekend daytime).
    static func suggestSlot(for r: Reminder, from now: Date = Date()) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let wd = cal.component(.weekday, from: day)
        let weekend = (wd == 1 || wd == 7)
        var c = cal.dateComponents([.year, .month, .day], from: day)
        c.hour = weekend ? 11 : 18; c.minute = 0
        return cal.date(from: c) ?? day
    }

    static func plan(_ overdue: [Reminder], from now: Date = Date()) -> [RescheduleChange] {
        guard !overdue.isEmpty else { return [] }
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: now)

        // Next 7 days starting tomorrow.
        var days: [(date: Date, weekend: Bool)] = []
        for offset in 1...7 {
            guard let d = cal.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let wd = cal.component(.weekday, from: d)   // 1 = Sun, 7 = Sat
            days.append((d, wd == 1 || wd == 7))
        }

        // Weighted quotas — weekends carry 2× a weekday.
        let count = overdue.count
        let weights = days.map { $0.weekend ? 2.0 : 1.0 }
        let totalW = weights.reduce(0, +)
        var quota = weights.map { Int((Double(count) * $0 / totalW).rounded(.down)) }
        var remainder = count - quota.reduce(0, +)
        let fracs = (0..<days.count).map { Double(count) * weights[$0] / totalW - Double(quota[$0]) }
        for idx in fracs.enumerated().sorted(by: { $0.element > $1.element }).map({ $0.offset }) {
            if remainder <= 0 { break }
            quota[idx] += 1; remainder -= 1
        }

        // High priority first, then oldest due first → earliest days.
        let sorted = overdue.sorted { a, b in
            let pa = a.priorityOrNormal == "high" ? 0 : 1
            let pb = b.priorityOrNormal == "high" ? 0 : 1
            if pa != pb { return pa < pb }
            return (parseDate(a.dueDate) ?? .distantPast) < (parseDate(b.dueDate) ?? .distantPast)
        }

        var changes: [RescheduleChange] = []
        var i = 0
        for (di, day) in days.enumerated() {
            let q = quota[di]
            guard q > 0 else { continue }
            let win = day.weekend ? weekendWindow : weekdayWindow
            for k in 0..<q {
                guard i < sorted.count else { break }
                let r = sorted[i]; i += 1
                // Even spacing within the day's free window.
                let t = win.start + (win.end - win.start) * Double(k + 1) / Double(q + 1)
                let hour = Int(t)
                let minute = Int(((t - Double(hour)) * 60 / 15).rounded()) * 15
                var comps = cal.dateComponents([.year, .month, .day], from: day.date)
                comps.hour = min(hour, 23); comps.minute = min(minute, 45)
                let newDate = cal.date(from: comps) ?? day.date
                changes.append(RescheduleChange(id: r.id, title: displayTitle(r),
                                                oldDue: r.dueDate, newDue: iso(newDate), newDate: newDate))
            }
        }
        return changes
    }
}
