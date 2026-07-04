// Models.swift — Nudge (iOS)
// Bundle ID: uk.flouty.nudge
// Codable models mirroring the web app's JSON so iOS shares the same Supabase data.

import Foundation

// A flexible JSON value so we can round-trip `settings` (mixed bool/string) without losing it.
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }
}

struct Recurrence: Codable, Hashable {
    var freq: String          // hourly / daily / weekly / monthly / yearly
    var interval: Int?
    var until: String?        // ISO date — stop repeating after this (optional)
}

/// One phase of a routine's escalating frequency, e.g. "every 3 days until 1 Jul".
/// A step with `until == nil` is the final, open-ended phase.
struct EscalationStep: Codable, Hashable, Identifiable {
    var id: String            // stable id so SwiftUI ForEach edits/deletes are safe
    var everyDays: Int        // repeat interval in days while this phase is active
    var until: String?        // ISO date this phase ends (nil = final phase)

    init(everyDays: Int, until: String? = nil, id: String = UUID().uuidString) {
        self.id = id; self.everyDays = everyDays; self.until = until
    }
    // Decode tolerates old/foreign JSON missing `id` (web preserves unknown keys).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        everyDays = try c.decode(Int.self, forKey: .everyDays)
        until = try? c.decode(String.self, forKey: .until)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
    }
}

struct Subtask: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var done: Bool
}

struct Reminder: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var notes: String?
    var dueDate: String?      // ISO 8601 string, matches web
    var hasTime: Bool?
    var listId: String?
    var priority: String?     // "low" | "normal" | "high"
    var completed: Bool?
    var completedAt: String?
    var recurrence: Recurrence?
    var subtasks: [Subtask]?
    var remindBefore: Int?    // legacy single early alert (minutes before due) — kept for back-compat
    var remindBefores: [Int]? // multiple early alerts, minutes before due (e.g. [10080, 1440, 60])
    var tz: String?           // pinned IANA timezone, or nil = local
    var url: String?          // an attached link
    var location: String?     // a place / address (tap → Maps)
    var lat: Double?          // location coordinate
    var lng: Double?
    var section: String?      // named section within its list (nil = ungrouped)
    var createdAt: String?
    var updatedAt: String?    // last local edit; used as tiebreak vs Apple's lastModifiedDate
    var source: String?       // "manual" | "apple" | "studytrack" | "finance" | "auto"
    var snoozedUntil: String?
    var dismissed: Bool?
    var pinned: Bool? = nil   // kept on the Home dashboard regardless of due date
    // Nightly routine (e.g. KP / Epiduo): if not ticked by next morning, the app asks
    // "did you do it last night?" on first open. Advances in place rather than spawning
    // copies. `escalation` ramps the frequency over time; `escalateAskNext` is when to
    // next prompt "ready to step up?" (adaptive, skin-based).
    var routine: Bool? = nil
    var escalation: [EscalationStep]? = nil
    var escalateAskNext: String? = nil
    // "Prep" link: this reminder is kept `prepDaysBefore` days before another reminder's
    // (`prepFor`) due date, at prepHour:prepMinute. When the target moves (e.g. a weekly
    // routine rolls forward), this one's date follows and it re-opens for the new cycle.
    // Used for "Buy Ginger Shot Ingredients" → "Make Ginger Shots".
    var prepFor: String? = nil
    var prepDaysBefore: Int? = nil
    var prepHour: Int? = nil
    var prepMinute: Int? = nil
    // "Urgent": schedule a real AlarmKit alarm (rings + Live Activity at the due time, even
    // when the app is closed) — like Apple Reminders' urgent reminders. iOS 26+.
    var urgent: Bool? = nil
    // Grouping: reminders that share a `groupId` are shown collapsed into one "group card"
    // to clear clutter; tapping expands to reveal all members. `groupTitle` is denormalised
    // onto each member so any client can render the group with no lookup table (keeps the
    // web PWA able to display/expand groups the phone made). `groupSource` = "ai" | "manual".
    // Fully NON-DESTRUCTIVE: ungrouping just clears these three fields; nothing is deleted and
    // each reminder keeps its own due date, list, etc.
    var groupId: String? = nil
    var groupTitle: String? = nil
    var groupSource: String? = nil

    var isCompleted: Bool { completed ?? false }
    var isGrouped: Bool { (groupId?.isEmpty == false) }
    var listIdOrDefault: String { listId ?? "reminders" }
    var priorityOrNormal: String { priority ?? "normal" }

    /// All early-alert offsets (minutes before due), newest field first, falling back to
    /// the legacy single value. De-duplicated, positive, soonest-to-due last.
    var earlyAlerts: [Int] {
        let raw = remindBefores ?? remindBefore.map { [$0] } ?? []
        return Array(Set(raw.filter { $0 > 0 })).sorted(by: >)
    }

    /// Recurring / nightly / escalating reminders that the end-of-day AI carry-over must
    /// NEVER move. This is the single structural gate — anything that repeats in any way is
    /// off-limits, no matter what the AI suggests. Checked both when building the AI's input
    /// (so it never even sees these) and again at the apply step (belt-and-braces).
    var isProtectedFromAI: Bool {
        if routine == true { return true }
        if let e = escalation, !e.isEmpty { return true }
        if let r = recurrence, r.freq != "none" { return true }
        return false
    }
}

struct ReminderList: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var builtin: Bool?
    var special: String?
    var linked: String?
}

struct SmartRules: Codable, Hashable {
    var tags: [String]?
    var priority: String?
    var overdue: Bool?
    var noDate: Bool?
    var listId: String?
}

struct SmartList: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var rules: SmartRules?
}

// The whole `data` blob stored in the Supabase `nudge_data` row.
struct NudgeData: Codable {
    var reminders: [Reminder]
    var lists: [ReminderList]
    var smartLists: [SmartList]?
    var settings: [String: JSONValue]?
}
