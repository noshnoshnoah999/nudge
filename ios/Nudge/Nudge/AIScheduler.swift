// AIScheduler.swift — Nudge (iOS)
// Claude-powered Smart Reschedule. Sends the overdue reminders + the user's busy calendar
// times to the Anthropic Messages API and asks Claude to spread them intelligently across
// the coming week, returning structured JSON. Falls back to the heuristic SmartScheduler
// (handled by the caller) if there's no API key or the call fails.
//
// Swift has no official Anthropic SDK, so this uses raw HTTPS via URLSession. The key is the
// user's own Anthropic key (stored locally); requests go straight to Anthropic.

import Foundation

enum AIScheduler {
    struct Move: Decodable { let id: String; let datetime: String }
    private struct Out: Decodable { let moves: [Move] }

    static let defaultModel = "claude-opus-4-8"

    /// Ask Claude for new times for the overdue reminders. Throws on any network/parse error
    /// so the caller can fall back to the heuristic planner.
    static func plan(overdue: [Reminder], busy: [DateInterval], now: Date,
                     apiKey: String, model: String) async throws -> [RescheduleChange] {
        guard !overdue.isEmpty else { return [] }
        let cal = Calendar.current
        let isoOffset = ISO8601DateFormatter()
        isoOffset.formatOptions = [.withInternetDateTime]

        let remLines = overdue.map { r -> String in
            let due = parseDate(r.dueDate)
            let overdueDays = due.map { cal.dateComponents([.day], from: $0, to: now).day ?? 0 } ?? 0
            let timeOfDay = ((r.hasTime ?? false), due)
            let t: String = (timeOfDay.0 && timeOfDay.1 != nil) ? hhmm(timeOfDay.1!) : "no set time"
            return "- id=\(r.id) | \"\(displayTitle(r))\" | priority=\(r.priorityOrNormal) | \(overdueDays)d overdue | usual time: \(t)"
        }.joined(separator: "\n")
        let busyLines = busy.prefix(80)
            .map { "- \(isoOffset.string(from: $0.start)) → \(isoOffset.string(from: $0.end))" }
            .joined(separator: "\n")

        let system = """
        You reschedule a user's OVERDUE reminders into the NEXT 7 DAYS for a reminders app.
        Rules:
        - Spread them out so the backlog clears — don't pile everything onto one day; weekends can carry a little more.
        - High-priority and most-overdue items get earlier days.
        - Choose a sensible time of day from each reminder's wording (gym/breakfast/meds → morning; lunch → midday; study/work/call/email → afternoon; dinner/groceries/skincare → evening). If it already had a usual time, stay close to it.
        - NEVER schedule a reminder during one of the user's BUSY calendar intervals — pick a free time.
        - Keep all times between 07:00 and 22:00 local.
        - Return a datetime for EVERY reminder id, in LOCAL time, ISO-8601 with no timezone suffix (e.g. 2026-06-25T18:00:00).
        """
        let userMsg = """
        NOW (local): \(isoOffset.string(from: now))

        OVERDUE REMINDERS:
        \(remLines)

        BUSY CALENDAR INTERVALS (do not schedule over these):
        \(busyLines.isEmpty ? "(none)" : busyLines)
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "moves": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "datetime": ["type": "string"]
                    ],
                    "required": ["id", "datetime"],
                    "additionalProperties": false
                ]]
            ],
            "required": ["moves"],
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
            throw NSError(domain: "AIScheduler", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        // output_config.format guarantees content[0] is text with valid JSON for our schema.
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = (content.first { ($0["type"] as? String) == "text" }?["text"]) as? String,
              let outData = text.data(using: .utf8) else {
            throw NSError(domain: "AIScheduler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])
        }
        let out = try JSONDecoder().decode(Out.self, from: outData)

        let byId = Dictionary(overdue.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changes: [RescheduleChange] = []
        for m in out.moves {
            guard let r = byId[m.id], let date = parseFlexible(m.datetime) else { continue }
            changes.append(RescheduleChange(id: r.id, title: displayTitle(r),
                                            oldDue: r.dueDate, newDue: iso(date), newDate: date))
        }
        return changes
    }

    private static func hhmm(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
    private static func parseFlexible(_ s: String) -> Date? {
        if let d = parseDate(s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
