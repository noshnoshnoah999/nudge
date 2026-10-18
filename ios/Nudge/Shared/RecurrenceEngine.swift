// RecurrenceEngine.swift — Nudge (shared: app + widget extension)
//
// THE SINGLE SOURCE OF TRUTH for "when does this repeating thing happen next".
//
// WHY THIS FILE EXISTS
//   Completing a reminder used to mean two different things depending on where you tapped:
//     • In the app, NudgeStore.toggleComplete knew that a nightly ROUTINE never really
//       completes (it rolls forward and leaves a history snapshot) and that a plain
//       RECURRING reminder spawns its next occurrence.
//     • In the Today widget, CompleteReminderWidgetIntent knew none of that. It just set
//       completed = true. So on 2026-08-04 Noah ticked "Epiduo Night" and "KP Body Scrub
//       Night" off the widget and both routines died on the spot instead of rolling over.
//   The date math now lives here, in a file both targets compile, so the two paths cannot
//   drift apart again. NudgeStore delegates to it; the widget calls it directly.
//
// DESIGN CONSTRAINTS
//   • Pure Foundation. No NudgeStore, no SwiftUI, no Reminder model — the widget target does
//     NOT compile Nudge/Models.swift (Nudge/ is an app-only synchronized group), so this file
//     cannot mention Recurrence or EscalationStep. Callers map their own types onto the small
//     `Rule` / `EscalationPhase` value types below.
//   • No global helpers. `parseDate` and `iso` already exist at file scope in NudgeStore.swift;
//     redeclaring them here would collide in the app target, so ours are nested and private.
//   • `nonisolated` because the project builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor,
//     which would otherwise pin these to the main actor and make them unreachable from the
//     widget intent's non-isolated perform(). Everything here is pure — nothing to protect.
//   • `now` is injected everywhere rather than read implicitly, so the behaviour is testable
//     and so a single completion computes every date against one consistent instant.

import Foundation
import CryptoKit

nonisolated enum RecurrenceEngine {

    // MARK: - Inputs

    /// A repeat rule, mapped from `Recurrence` (app) or raw JSON (widget).
    ///
    /// `nonisolated` on each nested type as well as the enum: with default MainActor
    /// isolation, an unannotated nested type would be inferred @MainActor and could not be
    /// built inside the widget intent's non-isolated code path.
    nonisolated struct Rule {
        var freq: String        // hourly / daily / weekly / monthly / yearly
        var interval: Int?
        var until: String?      // ISO — stop repeating after this instant

        init(freq: String, interval: Int? = nil, until: String? = nil) {
            self.freq = freq; self.interval = interval; self.until = until
        }
        /// A rule of "none" is the same as no rule at all — matches how the app stores it.
        var isRepeating: Bool { freq != "none" && !freq.isEmpty }
    }

    /// One phase of a routine's escalating frequency, e.g. "every 3 days until 1 Jul".
    /// A phase with `until == nil` is the final, open-ended one.
    nonisolated struct EscalationPhase {
        var everyDays: Int
        var until: String?

        init(everyDays: Int, until: String? = nil) {
            self.everyDays = everyDays; self.until = until
        }
    }

    /// What completing an item actually means. Both call sites branch on this so they can
    /// never disagree about which rule applies — the exact disagreement that caused the bug.
    nonisolated enum CompletionKind: Equatable {
        /// A nightly routine: never completes. Roll it forward, leave a history snapshot.
        case routine
        /// A repeating reminder: complete this one, spawn the next occurrence.
        case repeating
        /// Everything else, including a repeating series that has passed its end date:
        /// a plain, final completion.
        case oneOff
    }

    /// Classify a completion. `isRoutine` wins over `rule` — a routine with a recurrence
    /// (Epiduo has both) is still a routine, exactly as NudgeStore.toggleComplete orders it.
    static func completionKind(isRoutine: Bool, rule: Rule?) -> CompletionKind {
        if isRoutine { return .routine }
        if let r = rule, r.isRepeating { return .repeating }
        return .oneOff
    }

    // MARK: - Plain recurrence

    /// Advance a due date to the next FUTURE occurrence of `rule`.
    ///
    /// Steps by the rule's interval at least once and keeps stepping until the result is in
    /// the future, so ticking a long-overdue weekly item lands on the next real occurrence
    /// rather than another date in the past. Returns nil when the series has ended (past
    /// `until`), when the date can't be parsed, or when the frequency is unrecognised —
    /// in every one of those cases the caller should just complete the item outright.
    static func nextOccurrence(afterDue dueStr: String?, rule: Rule, now: Date = Date()) -> String? {
        guard let due = parse(dueStr) else { return nil }
        let cal = Calendar.current
        let step = max(1, rule.interval ?? 1)
        let comp: Calendar.Component
        switch rule.freq {
        case "hourly":  comp = .hour
        case "daily":   comp = .day
        case "weekly":  comp = .weekOfYear
        case "monthly": comp = .month
        case "yearly":  comp = .year
        default: return nil
        }
        var next = due
        var guardCount = 0
        repeat {
            next = cal.date(byAdding: comp, value: step, to: next) ?? next
            guardCount += 1
        } while next <= now && guardCount < 2000
        // Respect an "end repeat" date.
        if let u = parse(rule.until), next > u { return nil }
        return stamp(next)
    }

    // MARK: - Successor identity

    /// The id of the occurrence that completing `parentId` spawns.
    ///
    /// DETERMINISTIC ON PURPOSE (2026-10-18). It used to be a fresh random id at every spawn
    /// site — the app's toggleComplete, the widget intent, and RemindersSync — so the same
    /// completion arriving twice (a double tap, an untick + re-tick, a stale widget row, the
    /// widget AND the app) created two "next" reminders with different ids, and per-item sync
    /// faithfully kept both. Noah saw reminders repeated 2–5 times.
    ///
    /// Deriving the id from the parent means every path names the SAME successor, so a repeat
    /// lands on one row and sync merges it instead of multiplying it. Each occurrence spawns
    /// at most one successor, so the parent id alone is enough — the next DATE is deliberately
    /// not part of the key, because `nextOccurrence` depends on "now" and two devices
    /// completing either side of midnight would otherwise disagree.
    ///
    /// Shape: "r" + 12 upper-case hex chars. Legacy random ids are "r" + a UUID prefix, which
    /// always contains a "-" at position 9, so the two can never collide.
    static func successorId(of parentId: String) -> String {
        let digest = SHA256.hash(data: Data("nudge-next|\(parentId)".utf8))
        return "r" + digest.prefix(6).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Nightly routines

    /// The routine's current repeat interval in days.
    ///
    /// Escalation phases take priority: the first phase whose `until` is still in the future
    /// wins, else the open-ended one, else the last. Falls back to the recurrence rule for
    /// daily/weekly, and finally to 1 — a routine always has some cadence.
    static func routineIntervalDays(escalation: [EscalationPhase]?,
                                    rule: Rule?,
                                    now: Date = Date()) -> Int {
        if let steps = escalation, !steps.isEmpty {
            for s in steps {
                if let u = parse(s.until) {
                    if now < u { return max(1, s.everyDays) }
                } else {
                    return max(1, s.everyDays)
                }
            }
            return max(1, steps.last?.everyDays ?? 1)
        }
        if let rec = rule {
            switch rec.freq {
            case "daily":  return max(1, rec.interval ?? 1)
            case "weekly": return 7 * max(1, rec.interval ?? 1)
            default: break
            }
        }
        return 1
    }

    /// The evening time-of-day a routine fires at, taken from its current due date.
    /// Defaults to 21:00 when there is no parseable due date.
    static func eveningComponents(ofDue dueStr: String?) -> (hour: Int, minute: Int) {
        if let d = parse(dueStr) {
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 21, c.minute ?? 0)
        }
        return (21, 0)
    }

    /// The due date a routine should roll forward to after being done on `night`.
    ///
    /// Anchors on the night the occurrence was DUE, not on "now", so ticking a lapsed routine
    /// from the widget schedules the same next date the morning check-in would. Steps by the
    /// active interval at least once (so doing it early still advances) and keeps stepping
    /// until the result is in the future. Keeps the routine's evening time-of-day.
    static func advancedRoutineDue(night: Date,
                                   currentDue dueStr: String?,
                                   escalation: [EscalationPhase]?,
                                   rule: Rule?,
                                   now: Date = Date()) -> String {
        let cal = Calendar.current
        let interval = routineIntervalDays(escalation: escalation, rule: rule, now: now)
        let (h, m) = eveningComponents(ofDue: dueStr)
        var c = cal.dateComponents([.year, .month, .day], from: night)
        c.hour = h; c.minute = m
        var next = cal.date(from: c) ?? night
        var guardN = 0
        repeat {
            next = cal.date(byAdding: .day, value: interval, to: next) ?? next
            guardN += 1
        } while next <= now && guardN < 2000
        return stamp(next)
    }

    // MARK: - Date helpers (private — the app target already has global ones)

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Tolerates both stamp shapes Nudge has written over its life (with and without
    /// fractional seconds), matching NudgeStore.parseDate exactly.
    static func parse(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        return isoWithFraction.date(from: s) ?? isoPlain.date(from: s)
    }

    /// The canonical stamp format Nudge writes everywhere.
    static func stamp(_ d: Date) -> String { isoWithFraction.string(from: d) }
}
