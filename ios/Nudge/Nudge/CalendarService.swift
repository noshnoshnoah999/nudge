// CalendarService.swift — Nudge (iOS)
// Reads the user's Apple Calendar events (read-only) so Nudge can:
//  • warn when you schedule/reschedule a reminder on top of an event, and
//  • keep Smart Reschedule from dropping reminders into times you're busy.
// Separate from RemindersSync (which is the Reminders entity) — this is the Events entity,
// a distinct EventKit permission.

import Foundation
import EventKit
import Combine

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let store = EKEventStore()
    private var cache: [EKEvent] = []

    @Published private(set) var hasAccess = false

    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Ask for Calendar (events) access once, then load the upcoming events.
    func requestAccessIfNeeded() async {
        if authorized { hasAccess = true; refresh(); return }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        hasAccess = granted
        if granted { refresh() }
    }

    /// Reload the event cache for roughly the next month (cheap; call on launch/foreground
    /// and right before a Smart Reschedule).
    func refresh(days: Int = 35) {
        guard authorized else { cache = []; hasAccess = false; return }
        hasAccess = true
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let end = cal.date(byAdding: .day, value: days, to: now) ?? now
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        cache = store.events(matching: pred)
    }

    /// The first timed event (ignoring all-day) whose span contains `date` — i.e. you'd be
    /// busy if a reminder fired then.
    private func conflictingEvent(at date: Date) -> EKEvent? {
        cache.first { !$0.isAllDay && date >= $0.startDate && date < $0.endDate }
    }

    /// A human label for a clash at `date`, e.g. "Maths class (2:00–3:00 PM)", or nil if free.
    func conflictDescription(at date: Date) -> String? {
        guard let e = conflictingEvent(at: date) else { return nil }
        let f = DateFormatter(); f.timeStyle = .short
        let title = (e.title?.isEmpty == false) ? e.title! : "an event"
        return "\(title) (\(f.string(from: e.startDate))–\(f.string(from: e.endDate)))"
    }

    /// Busy spans (timed events only) for the Smart-Reschedule planner to avoid.
    func busyIntervals() -> [DateInterval] {
        cache.compactMap { e in
            guard !e.isAllDay, e.endDate > e.startDate else { return nil }
            return DateInterval(start: e.startDate, end: e.endDate)
        }
    }
}
