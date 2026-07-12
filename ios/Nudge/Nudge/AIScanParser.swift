// AIScanParser.swift — Nudge (iOS / macCatalyst)
// Turns raw OCR TEXT (from ReminderScanner) into a list of structured reminders:
// title + optional date/time. Mirrors AIGrouper / AIScheduler: same Anthropic endpoint,
// same headers, same json_schema output, same Sonnet model chosen by the caller.
//
// PRIVACY: only the extracted TEXT is sent — never the image. The image stays on the device.

import Foundation

/// One reminder the AI pulled out of the scanned text. `dateTime` is a local ISO string with
/// NO timezone suffix (e.g. 2026-07-15T15:00:00) when the AI is confident about a due moment;
/// nil when the text implies no date. `hasTime` is false when only a day (not a clock time)
/// was implied — the UI treats those as all-day.
struct ScannedItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var dateTime: Date?     // nil = no date detected (user sets one, or saves undated)
    var hasTime: Bool       // only meaningful when dateTime != nil
}

enum AIScanParser {
    private struct Item: Decodable {
        let title: String
        let datetime: String?   // local ISO, no tz suffix, or null
        let has_time: Bool?
    }
    private struct Out: Decodable { let items: [Item] }

    enum ParseError: LocalizedError {
        case empty
        case api(String)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .empty: return "No reminders found in that text."
            case .api(let m): return m
            case .badResponse: return "Couldn't understand the AI response. Try again."
            }
        }
    }

    /// Ask Claude to split the OCR text into individual reminders with dates/times.
    /// `now` anchors relative dates ("Friday", "tomorrow"). Throws on network/parse error so
    /// the caller can show a retry.
    static func parse(text: String, now: Date = Date(), apiKey: String, model: String) async throws -> [ScannedItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.empty }

        let localISO: (Date) -> String = { d in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: d)
        }
        let readable: (Date) -> String = { d in
            let f = DateFormatter(); f.dateFormat = "EEE d MMM yyyy HH:mm"; return f.string(from: d)
        }

        let system = """
        You extract reminders from text a user captured from a photo or screenshot of a list \
        (another app, a note, or paper). The text may be messy OCR: fix obvious typos and \
        casing, but keep the user's wording.

        Return an "items" array. Each item:
        - title: a tidy short reminder title, no trailing punctuation.
        - datetime: if — and ONLY if — the text clearly states or implies a due date, a local \
          ISO-8601 datetime with NO timezone suffix (e.g. 2026-07-15T15:00:00). Otherwise null. \
          Interpret relative words ("today", "tomorrow", "Friday", "next week") against NOW below. \
          Never invent a date that isn't supported by the text — when unsure, use null.
        - has_time: true only if a specific clock time was given/implied (e.g. "3pm", "call at \
          9"); false if only a day was implied (then use 09:00 in the datetime as a placeholder). \
          Ignore has_time when datetime is null.

        Rules:
        - One item per distinct task. Split a run-on line into separate tasks only when it clearly \
          lists several ("milk, eggs, bread" → three items). Don't merge unrelated lines.
        - Drop noise that isn't a task: headers, dates on their own line, page numbers, app UI \
          text, checkbox glyphs, list titles.
        - Do NOT guess dates. A list with no dates should return items that ALL have datetime null. \
          It is correct and expected for many or all items to have no date.
        """
        let userMsg = """
        NOW (local): \(localISO(now)) — today is \(readable(now)).

        SCANNED TEXT:
        \(trimmed)
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "items": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "datetime": ["type": ["string", "null"]],
                        "has_time": ["type": "boolean"]
                    ],
                    "required": ["title", "datetime", "has_time"],
                    "additionalProperties": false
                ]]
            ],
            "required": ["items"],
            "additionalProperties": false
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
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
            throw ParseError.api(msg)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let out = (content.first { ($0["type"] as? String) == "text" }?["text"]) as? String,
              let outData = out.data(using: .utf8) else {
            throw ParseError.badResponse
        }
        let decoded = try JSONDecoder().decode(Out.self, from: outData)

        // Parse the local ISO strings back into Dates (no tz suffix → interpret as local).
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        return decoded.items.compactMap { raw in
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var date: Date? = nil
            if let s = raw.datetime, !s.isEmpty {
                // Tolerate a trailing "Z" or fractional seconds if the model adds them.
                date = parser.date(from: String(s.prefix(19)))
            }
            let hasTime = (date != nil) && (raw.has_time ?? false)
            return ScannedItem(title: title, dateTime: date, hasTime: hasTime)
        }
    }
}
