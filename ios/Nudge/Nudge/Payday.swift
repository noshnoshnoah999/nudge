// Payday.swift — Nudge (iOS)
// Noah is paid on the 15th of each month — but if the 15th lands on a weekend he's
// paid the Friday of that week. Buy reminders and the monthly "Send to Mum" reminder
// anchor to this date. Kept in one place so iOS + web stay consistent (mirror in
// index.html `paydayInMonth` / `nextPayday`).

import Foundation

enum Payday {
    /// Payday for the month containing `date`: the 15th at 09:00, or the Friday before
    /// if the 15th is Sat (→14th) or Sun (→13th).
    static func inMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month], from: date)
        c.day = 15; c.hour = 9; c.minute = 0; c.second = 0
        let fifteenth = cal.date(from: c) ?? date
        switch cal.component(.weekday, from: fifteenth) {
        case 7:  return cal.date(byAdding: .day, value: -1, to: fifteenth) ?? fifteenth   // Sat → Fri 14
        case 1:  return cal.date(byAdding: .day, value: -2, to: fifteenth) ?? fifteenth   // Sun → Fri 13
        default: return fifteenth
        }
    }

    /// Next payday at/after `from`: this month's if it hasn't passed, else next month's.
    static func next(from: Date = Date()) -> Date {
        let cal = Calendar.current
        let thisMonth = inMonth(from)
        if cal.startOfDay(for: thisMonth) >= cal.startOfDay(for: from) { return thisMonth }
        let nextMonth = cal.date(byAdding: .month, value: 1, to: from) ?? from
        return inMonth(nextMonth)
    }

    /// Is today payday?
    static func isToday(_ date: Date = Date()) -> Bool {
        Calendar.current.isDate(inMonth(date), inSameDayAs: date)
    }
}
