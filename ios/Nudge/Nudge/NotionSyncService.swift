// NotionSyncService.swift — Nudge (iOS)
// Manual, one-way push: Nudge reminders -> the "To Do List" database in Notion (under the
// TIHS page). Triggered only by the user tapping the header button — never automatic, never
// a background sync, so there's no surprise network traffic or surprise Notion writes.
//
// SCOPE: a reminder is pushed only if `pushToNotion == true` OR its list is named "Study"
// (case-insensitive). Nothing else in Nudge goes to Notion. This was a deliberate, explicit
// decision — do not widen this to "all reminders" without asking first.
//
// INCREMENTAL: within scope, only reminders that are new or have changed since their last
// confirmed successful push are sent (compares `updatedAt` against `notionSyncedAt`). This
// keeps pushes fast and avoids hammering Notion's rate limit as the Study list grows.
//
// DEDUPE: every reminder carries a stable Nudge ID into its own hidden "Nudge ID" property in
// Notion. A push first queries Notion for an existing row with that ID; if found, it PATCHes
// that page in place, otherwise it POSTs a new page. This is what makes repeated pushes safe
// — re-running never creates duplicate rows.
//
// `notionSyncedAt` is stamped ONLY after a confirmed 2xx response for that specific reminder.
// If the push fails partway (network drop, rate limit, Notion outage), whatever didn't
// confirm stays unstamped and will be retried on the next push — nothing is silently skipped.

import Foundation

enum NotionSyncError: LocalizedError {
    case notConfigured
    case network(String)
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Notion isn't set up yet — add your integration token and database ID in Settings."
        case .network(let m): return "Network error: \(m)"
        case .api(let code, let m): return "Notion error (\(code)): \(m)"
        }
    }
}

struct NotionPushResult {
    var pushedCount: Int
    var failedCount: Int
}

enum NotionSyncService {
    private static let apiBase = "https://api.notion.com/v1"
    private static let apiVersion = "2022-06-28"

    /// True if this reminder is in the Notion-push scope: either explicitly flagged, or
    /// filed under a list literally named "Study" (matches how Noah already organises
    /// schoolwork reminders today).
    private static func inScope(_ r: Reminder, lists: [ReminderList]) -> Bool {
        if r.pushToNotion == true { return true }
        guard let listId = r.listId,
              let list = lists.first(where: { $0.id == listId }) else { return false }
        return list.name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Study") == .orderedSame
    }

    /// True if this reminder needs (re)pushing: never synced, or edited since its last sync.
    private static func needsPush(_ r: Reminder) -> Bool {
        guard let syncedAt = r.notionSyncedAt else { return true }
        guard let updatedAt = r.updatedAt else { return true }
        return updatedAt > syncedAt   // ISO 8601 strings compare lexicographically in order
    }

    /// Pushes every in-scope, out-of-date reminder to Notion. Returns the IDs that were
    /// confirmed pushed (caller stamps `notionSyncedAt` on those) plus a summary count.
    /// Reminders that fail to push are simply left out of `succeededIds` — they'll be
    /// retried on the next tap.
    static func push(reminders: [Reminder], lists: [ReminderList]) async throws -> (succeededIds: [String], result: NotionPushResult) {
        guard NotionKeyStore.isConfigured else { throw NotionSyncError.notConfigured }
        let token = NotionKeyStore.token
        let databaseId = NotionKeyStore.databaseId

        let toPush = reminders.filter { inScope($0, lists: lists) && needsPush($0) }
        var succeeded: [String] = []
        var failed = 0

        for reminder in toPush {
            do {
                let listName = lists.first(where: { $0.id == reminder.listId })?.name
                if let existingPageId = try await findPage(nudgeId: reminder.id, databaseId: databaseId, token: token) {
                    try await updatePage(pageId: existingPageId, reminder: reminder, listName: listName, token: token)
                } else {
                    try await createPage(databaseId: databaseId, reminder: reminder, listName: listName, token: token)
                }
                succeeded.append(reminder.id)
                // Notion's documented limit is an average of ~3 requests/sec. A tiny pause
                // between reminders (each of which is 1-2 requests) keeps us comfortably
                // under that without meaningfully slowing the button down.
                try? await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                failed += 1
                // Keep going — one bad reminder (e.g. a title Notion rejects) shouldn't
                // block the rest of the push.
                continue
            }
        }

        return (succeeded, NotionPushResult(pushedCount: succeeded.count, failedCount: failed))
    }

    // MARK: - Notion API calls

    private static func authorizedRequest(_ path: String, method: String, token: String) -> URLRequest {
        var req = URLRequest(url: URL(string: apiBase + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private static func send(_ req: URLRequest) async throws -> [String: Any] {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw NotionSyncError.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else { throw NotionSyncError.network("no response") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let message = (json["message"] as? String) ?? "unknown error"
            throw NotionSyncError.api(http.statusCode, message)
        }
        return json
    }

    /// Looks up an existing Notion page by the hidden "Nudge ID" property. Returns its page
    /// ID if found, or nil if this reminder has never been pushed before.
    private static func findPage(nudgeId: String, databaseId: String, token: String) async throws -> String? {
        var req = authorizedRequest("/databases/\(databaseId)/query", method: "POST", token: token)
        let filter: [String: Any] = [
            "filter": [
                "property": "Nudge ID",
                "rich_text": ["equals": nudgeId]
            ],
            "page_size": 1
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: filter)
        let json = try await send(req)
        guard let results = json["results"] as? [[String: Any]], let first = results.first,
              let id = first["id"] as? String else { return nil }
        return id
    }

    private static func createPage(databaseId: String, reminder: Reminder, listName: String?, token: String) async throws {
        var req = authorizedRequest("/pages", method: "POST", token: token)
        let body: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": properties(for: reminder, listName: listName)
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(req)
    }

    private static func updatePage(pageId: String, reminder: Reminder, listName: String?, token: String) async throws {
        var req = authorizedRequest("/pages/\(pageId)", method: "PATCH", token: token)
        let body: [String: Any] = ["properties": properties(for: reminder, listName: listName)]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(req)
    }

    /// Maps a Reminder onto the "To Do List" database's schema. Everything about the
    /// reminder that has a home in the schema is sent — this is a full field sync per
    /// in-scope reminder, not a partial one.
    private static func properties(for r: Reminder, listName: String?) -> [String: Any] {
        var props: [String: Any] = [
            "Title": ["title": [["text": ["content": r.title]]]],
            "Completed": ["checkbox": r.isCompleted],
            "Nudge ID": ["rich_text": [["text": ["content": r.id]]]]
        ]

        if let due = r.dueDate, let isoDate = notionDateString(from: due) {
            props["Due Date"] = ["date": ["start": isoDate]]
        } else {
            props["Due Date"] = ["date": NSNull()]
        }

        props["Notes"] = ["rich_text": [["text": ["content": r.notes ?? ""]]]]
        props["List"] = ["rich_text": [["text": ["content": listName ?? ""]]]]

        let locationText: String
        if let loc = r.location, !loc.isEmpty {
            locationText = loc
        } else if let lat = r.lat, let lng = r.lng {
            locationText = "\(lat), \(lng)"
        } else {
            locationText = ""
        }
        props["Location"] = ["rich_text": [["text": ["content": locationText]]]]

        return props
    }

    /// Notion's `date.start` wants a plain ISO 8601 date or datetime. Nudge's `dueDate` is
    /// already ISO 8601, so this just validates it round-trips rather than reformatting.
    private static func notionDateString(from iso: String) -> String? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if isoFormatter.date(from: iso) != nil { return iso }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if isoFormatter.date(from: iso) != nil { return iso }
        // Date-only strings (no time component) are already valid Notion date values.
        if iso.count == 10, iso.contains("-") { return iso }
        return nil
    }
}
