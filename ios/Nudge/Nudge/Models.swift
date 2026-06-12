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
    var remindBefore: Int?    // minutes before due
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

    var isCompleted: Bool { completed ?? false }
    var listIdOrDefault: String { listId ?? "reminders" }
    var priorityOrNormal: String { priority ?? "normal" }
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
