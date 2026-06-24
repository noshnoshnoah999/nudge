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

    // Both AI features (Smart Reschedule + end-of-day carry-over) run on Sonnet — a good
    // balance of quality and cost, and deliberately not Opus (priciest) or Haiku.
    static let defaultModel = "claude-sonnet-4-6"

    /// Ask Claude for new times for the overdue reminders. Throws on any network/parse error
    /// so the caller can fall back to the heuristic planner.
    static func plan(overdue: [Reminder], busy: [DateInterval], now: Date,
                     apiKey: String, model: String) async throws -> [RescheduleChange] {
        guard !overdue.isEmpty else { return [] }
        let cal = Calendar.current
        // Local ISO with no timezone suffix — the format we ask Claude to return.
        let localISO: (Date) -> String = { d in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: d)
        }
        let readable: (Date) -> String = { d in
            let f = DateFormatter(); f.dateFormat = "EEE d MMM HH:mm"; return f.string(from: d)
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now

        let remLines = overdue.map { r -> String in
            let due = parseDate(r.dueDate)
            let overdueDays = due.map { max(0, cal.dateComponents([.day], from: $0, to: now).day ?? 0) } ?? 0
            let cur = due.map { readable($0) } ?? "no date"
            return "- id=\(r.id) | \"\(displayTitle(r))\" | priority=\(r.priorityOrNormal) | currently \(cur) (\(overdueDays)d overdue)"
        }.joined(separator: "\n")
        let busyLines = busy.prefix(80)
            .map { "- \(localISO($0.start)) to \(localISO($0.end))" }
            .joined(separator: "\n")

        let system = """
        You reschedule a user's OVERDUE reminders. EVERY reminder below is in the past and needs a brand-new FUTURE time.

        Hard requirements:
        - Give each reminder a NEW datetime that is strictly AFTER "now". NEVER reuse a reminder's current (past) time — if your suggestion equals the current time, it is wrong.
        - Spread the reminders across the next 7 days, STARTING TOMORROW. Do NOT pile them all onto one day, and do not leave any on today. A few per day; weekends can take a little more.
        - Most-overdue and high-priority items get the earliest days.
        - Choose a sensible time of day from each reminder's wording: gym/breakfast/meds/shower → morning (~08:00); lunch → ~12:00; study/work/call/email/errand → afternoon (~15:00); dinner/cook/groceries/skincare → evening (~18:00); shopping/"buy" → late afternoon. If unclear, vary times so they don't all clump.
        - NEVER place a reminder inside one of the BUSY calendar intervals — pick a free time that day.
        - All times 07:00–22:00 local.
        - Output exactly one datetime per reminder id, LOCAL time, ISO-8601 with NO timezone suffix, e.g. 2026-06-25T18:00:00.
        """
        let userMsg = """
        NOW (local): \(localISO(now)) — i.e. today is \(readable(now)). Schedule everything for TOMORROW (\(readable(tomorrow))) or later.

        OVERDUE REMINDERS (each needs a new future datetime — do not keep the 'currently' time):
        \(remLines)

        BUSY CALENDAR INTERVALS (never schedule over these):
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
            guard let r = byId[m.id], let date = parseFlexible(m.datetime), date > now else { continue }
            changes.append(RescheduleChange(id: r.id, title: displayTitle(r),
                                            oldDue: r.dueDate, newDue: iso(date), newDate: date))
        }
        // If the model basically echoed the inputs (few real future moves), let the caller
        // fall back to the heuristic by returning empty.
        return changes.count >= max(1, overdue.count / 2) ? changes : []
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
