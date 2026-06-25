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

    // MARK: - Quick Catch (single free-text thought → smart date/time)

    /// What Claude returns for a caught thought.
    struct CatchSuggestion {
        let title: String        // cleaned-up reminder title
        let date: Date           // suggested due datetime (local)
        let hasTime: Bool        // false → all-day (no specific time made sense)
        let priority: String     // "low" | "normal" | "high"
        let reason: String       // one short line explaining the pick (shown on the confirm screen)
    }

    private struct CatchOut: Decodable {
        let title: String; let datetime: String; let has_time: Bool
        let priority: String; let reason: String
    }

    /// Read one free-text thought and choose a sensible future date + time for it, avoiding
    /// the user's busy calendar intervals and not piling onto days that are already loaded
    /// with reminders. Throws on any network/parse error so the caller can fall back to the
    /// heuristic (SmartScheduler.suggestSlot).
    static func suggestSlot(thought: String, upcoming: [Reminder], busy: [DateInterval],
                            now: Date, apiKey: String, model: String) async throws -> CatchSuggestion {
        let cal = Calendar.current
        let localISO: (Date) -> String = { d in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: d)
        }
        let readable: (Date) -> String = { d in
            let f = DateFormatter(); f.dateFormat = "EEE d MMM HH:mm"; return f.string(from: d)
        }
        // Per-day load over the next 14 days, so Claude can favour quieter days.
        let horizon = cal.date(byAdding: .day, value: 14, to: now) ?? now
        var perDay: [String: Int] = [:]
        for r in upcoming {
            guard let d = parseDate(r.dueDate), d >= now, d <= horizon, !(r.isCompleted) else { continue }
            let key = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d) }()
            perDay[key, default: 0] += 1
        }
        let loadLines = perDay.sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value) reminder(s)" }.joined(separator: "\n")
        let busyLines = busy.filter { $0.end >= now && $0.start <= horizon }.prefix(60)
            .map { "- \(localISO($0.start)) to \(localISO($0.end))" }.joined(separator: "\n")

        let system = """
        You turn a user's quickly-jotted thought into a single scheduled reminder. The user was busy and dumped it from their head — your job is to pick WHEN it should resurface.

        Return:
        - title: a tidy, short reminder title (fix casing/typos, keep their words; no trailing punctuation).
        - datetime: a sensible FUTURE local time, ISO-8601 with NO timezone suffix (e.g. 2026-06-26T18:00:00). Strictly after "now".
        - has_time: true if a specific time of day makes sense; false for a loose "someday that day" task (then use 09:00 as a placeholder).
        - priority: "high" only if the wording is clearly urgent/important, "low" if trivial/whenever, else "normal".
        - reason: ONE short friendly line (max ~10 words) explaining the pick, e.g. "Tomorrow evening — your day looks free".

        Rules:
        - If the thought names/implies a time ("tonight", "tomorrow 3pm", "before the weekend", "call the dentist") honour it.
        - Otherwise prefer the soonest QUIETER day (fewer existing reminders) within the next week, at a fitting time of day: gym/breakfast/meds/shower → ~08:00; lunch → ~12:00; study/work/call/email/errand → ~15:00; dinner/cook/groceries → ~18:00; chores/admin → late afternoon. Default loose thoughts to tomorrow.
        - NEVER place it inside a BUSY calendar interval.
        - All times 07:00–22:00 local.
        """
        let userMsg = """
        NOW (local): \(localISO(now)) — today is \(readable(now)).

        THE THOUGHT:
        \"\(thought.trimmingCharacters(in: .whitespacesAndNewlines))\"

        HOW LOADED EACH UPCOMING DAY ALREADY IS (prefer quieter days):
        \(loadLines.isEmpty ? "(nothing scheduled yet)" : loadLines)

        BUSY CALENDAR INTERVALS (never schedule over these):
        \(busyLines.isEmpty ? "(none)" : busyLines)
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "datetime": ["type": "string"],
                "has_time": ["type": "boolean"],
                "priority": ["type": "string", "enum": ["low", "normal", "high"]],
                "reason": ["type": "string"]
            ],
            "required": ["title", "datetime", "has_time", "priority", "reason"],
            "additionalProperties": false
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "system": system,
            "messages": [["role": "user", "content": userMsg]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]]
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "API error"
            throw NSError(domain: "AIScheduler", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = (content.first { ($0["type"] as? String) == "text" }?["text"]) as? String,
              let outData = text.data(using: .utf8) else {
            throw NSError(domain: "AIScheduler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])
        }
        let out = try JSONDecoder().decode(CatchOut.self, from: outData)
        guard var date = parseFlexible(out.datetime) else {
            throw NSError(domain: "AIScheduler", code: -3, userInfo: [NSLocalizedDescriptionKey: "Bad datetime"])
        }
        // Safety net: never hand back a past time.
        if date <= now { date = cal.date(byAdding: .hour, value: 18, to: cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)) ?? now }
        let pr = ["low", "normal", "high"].contains(out.priority) ? out.priority : "normal"
        let title = out.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return CatchSuggestion(title: title.isEmpty ? thought : title,
                               date: date, hasTime: out.has_time, priority: pr, reason: out.reason)
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
