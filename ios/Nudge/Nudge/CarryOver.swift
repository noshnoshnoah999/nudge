// CarryOver.swift — Nudge (iOS)
// End-of-day AI carry-over. At 23:50 local (or first launch after that point), Claude looks at
// the day's LEFT-OVER (incomplete, one-off) reminders and decides which few are important
// enough to roll to tomorrow. It carries only those; everything else stays put.
//
// SAFETY: recurring / nightly / escalating reminders are NEVER eligible. They're filtered out
// of the AI's input via `Reminder.isProtectedFromAI`, and filtered again at the apply step, so
// there is no code path by which a routine (Hair Wash, Epiduo, KP, Ivermectin, monthly
// payments, …) can be moved.

import Foundation
import SwiftUI
import Combine

// MARK: - Log model

/// One reminder the carry-over considered, with the AI's reason for moving / keeping it.
struct CarryItem: Codable, Identifiable, Hashable {
    var id: String          // reminder id
    var title: String
    var reason: String
    var oldDue: String?
    var newDue: String?     // set only if it was moved
}

/// One night's carry-over run.
struct CarryOverEntry: Codable, Identifiable, Hashable {
    var id: String          // the processed day key, yyyy-MM-dd
    var ranAt: String       // ISO timestamp
    var moved: [CarryItem]
    var kept: [CarryItem]
}

// MARK: - Persistent log (UserDefaults, last ~31 days)

/// Stores carry-over runs and drives the glowing red banner. ObservableObject so the banner
/// and history update live.
final class CarryOverLog: ObservableObject {
    static let shared = CarryOverLog()

    @Published private(set) var entries: [CarryOverEntry] = []   // newest first
    /// The id (day key) of a run the user hasn't reviewed yet → show the banner. nil = no banner.
    @Published var unseenDay: String?

    private let entriesKey = "carryOverEntries"
    private let unseenKey  = "carryOverUnseenDay"
    private let lastRunKey = "carryOverLastDay"   // last processed day key (run-once guard)

    private init() {
        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([CarryOverEntry].self, from: data) {
            entries = decoded
        }
        unseenDay = UserDefaults.standard.string(forKey: unseenKey)
        prune()
    }

    var lastProcessedDay: String? { UserDefaults.standard.string(forKey: lastRunKey) }

    func entry(for day: String) -> CarryOverEntry? { entries.first { $0.id == day } }
    var unseenEntry: CarryOverEntry? { unseenDay.flatMap(entry(for:)) }

    /// Record a completed run (even an empty one — keeps an honest history) and raise the banner.
    func record(_ entry: CarryOverEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        UserDefaults.standard.set(entry.id, forKey: lastRunKey)
        // Only surface the banner when there was actually something to report.
        if !entry.moved.isEmpty || !entry.kept.isEmpty {
            unseenDay = entry.id
            UserDefaults.standard.set(entry.id, forKey: unseenKey)
        }
        save()
    }

    /// Mark that this day's run has been processed even if nothing happened (so we don't retry
    /// the whole AI round-trip repeatedly within the same window).
    func markProcessed(_ day: String) {
        UserDefaults.standard.set(day, forKey: lastRunKey)
    }

    func dismissBanner() {
        unseenDay = nil
        UserDefaults.standard.removeObject(forKey: unseenKey)
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        entries.removeAll { e in (f.date(from: e.id).map { $0 < cutoff }) ?? false }
    }

    private func save() {
        prune()
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: entriesKey)
        }
    }
}

// MARK: - AI service

enum AICarryOver {
    private struct Decision: Decodable { let id: String; let carry: Bool; let reason: String }
    private struct Out: Decodable { let decisions: [Decision] }

    /// Ask Claude which of the day's leftover reminders deserve to roll to tomorrow.
    /// Returns one decision per input id. Throws on network/parse error.
    static func decide(leftovers: [Reminder], now: Date,
                       apiKey: String, model: String) async throws -> [String: (carry: Bool, reason: String)] {
        guard !leftovers.isEmpty else { return [:] }
        let readable: (Date) -> String = { d in
            let f = DateFormatter(); f.dateFormat = "EEE d MMM HH:mm"; return f.string(from: d)
        }
        let lines = leftovers.map { r -> String in
            let due = parseDate(r.dueDate).map { readable($0) } ?? "no time"
            let notes = (r.notes?.isEmpty == false) ? " | notes: \(r.notes!)" : ""
            return "- id=\(r.id) | \"\(displayTitle(r))\" | priority=\(r.priorityOrNormal) | was due \(due)\(notes)"
        }.joined(separator: "\n")

        let system = """
        You are the end-of-day triage for a personal reminders app. The user did NOT finish the \
        reminders below today. Decide, for EACH one, whether it is important/relevant enough to \
        carry over to tomorrow, or whether it should simply be left where it is.

        Principles:
        - Be selective. The whole point is to surface the few that genuinely matter — do NOT carry \
          everything over, that defeats the purpose. Most days only a handful deserve to move.
        - Carry over: time-sensitive, high-priority, or consequential tasks (payments, deadlines, \
          things others depend on, errands that block something).
        - Leave behind: low-value, vague, "nice to have", or stale items that have lost relevance.
        - Give a short, specific reason for every decision (one sentence).
        Output one decision object per id.
        """
        let userMsg = """
        Today is \(readable(now)). The user's LEFT-OVER reminders from today:
        \(lines)
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "decisions": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "carry": ["type": "boolean"],
                        "reason": ["type": "string"]
                    ],
                    "required": ["id", "carry", "reason"],
                    "additionalProperties": false
                ]]
            ],
            "required": ["decisions"],
            "additionalProperties": false
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": system,
            "messages": [["role": "user", "content": userMsg]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]]
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 45
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "API error"
            throw NSError(domain: "AICarryOver", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = (content.first { ($0["type"] as? String) == "text" }?["text"]) as? String,
              let outData = text.data(using: .utf8) else {
            throw NSError(domain: "AICarryOver", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])
        }
        let out = try JSONDecoder().decode(Out.self, from: outData)
        var map: [String: (carry: Bool, reason: String)] = [:]
        for d in out.decisions { map[d.id] = (d.carry, d.reason) }
        return map
    }
}
