// AIGrouper.swift — Nudge (iOS)
// Groups related reminders so the list feels less cluttered. Claude reads the ungrouped,
// incomplete, non-routine reminders and clusters the ones that genuinely belong together
// (by theme / project / place / errand), leaving the rest alone.
//
// SAFETY:
// - Grouping is purely a DISPLAY convenience: it only sets groupId/groupTitle on reminders.
//   Nothing is deleted, no due dates change, and ungrouping is one tap. This is why it is safe
//   to auto-apply overnight (unlike a destructive merge).
// - Recurring / nightly / escalating reminders are never candidates (filtered via
//   `Reminder.isProtectedFromAI` before the AI ever sees them).
// - The AI only ever REORGANISES the visible pile; it can't create, move, or complete anything.

import Foundation

/// One group the AI proposed: a short title and the member reminder ids.
struct ProposedGroup: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    var reminderIds: [String]
}

enum AIGrouper {
    private struct G: Decodable { let title: String; let ids: [String] }
    private struct Out: Decodable { let groups: [G] }

    /// Ask Claude to cluster the candidate reminders into a small number of named groups.
    /// Returns only groups with ≥2 members; every id is used at most once. Throws on
    /// network / parse error so the caller can fall back or retry.
    static func propose(candidates: [Reminder], apiKey: String, model: String) async throws -> [ProposedGroup] {
        guard candidates.count >= 2 else { return [] }

        let lines = candidates.map { r -> String in
            let notes = (r.notes?.isEmpty == false) ? " | notes: \(r.notes!)" : ""
            return "- id=\(r.id) | \"\(displayTitle(r))\"\(notes)"
        }.joined(separator: "\n")

        let system = """
        You tidy a personal reminders app by grouping related reminders so the list feels less \
        cluttered. Cluster the reminders below into a SMALL number of meaningful groups. Reason \
        for yourself about what actually belongs together — usually a shared theme, project, \
        place, or errand (e.g. all shopping items, all emails to send, everything about one trip). \
        Mix these signals with your own judgement; there is no fixed rule.

        Principles:
        - Only group reminders that genuinely belong together. Every group MUST have at least 2 members.
        - It is expected that many reminders stay ungrouped. Do NOT force everything into a group — \
          a few good groups beats many weak ones.
        - Give each group a short, clear title of 2–4 words.
        - Use each id at most once. Never place a reminder in two groups.
        - Only include groups you are genuinely confident about.
        """
        let userMsg = "Reminders to consider:\n\(lines)"

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "groups": ["type": "array", "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "ids": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["title", "ids"],
                    "additionalProperties": false
                ]]
            ],
            "required": ["groups"],
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
            throw NSError(domain: "AIGrouper", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = (content.first { ($0["type"] as? String) == "text" }?["text"]) as? String,
              let outData = text.data(using: .utf8) else {
            throw NSError(domain: "AIGrouper", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected response"])
        }
        let out = try JSONDecoder().decode(Out.self, from: outData)

        // Sanitise: keep only ids that were actually candidates, drop any id reused across
        // groups (first group wins), and require ≥2 valid members per group.
        let valid = Set(candidates.map { $0.id })
        var used = Set<String>()
        var result: [ProposedGroup] = []
        for g in out.groups {
            let ids = g.ids.filter { valid.contains($0) && !used.contains($0) }
            guard ids.count >= 2 else { continue }
            ids.forEach { used.insert($0) }
            let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(ProposedGroup(title: title.isEmpty ? "Group" : title, reminderIds: ids))
        }
        return result
    }
}
