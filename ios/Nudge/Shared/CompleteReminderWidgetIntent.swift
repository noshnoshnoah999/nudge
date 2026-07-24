// CompleteReminderWidgetIntent.swift — Nudge (shared: app + widget extension)
//
// The App Intent run by a tap on a reminder row in the Today widget. Because a widget
// Button(intent:) runs in the WIDGET'S process — where the app's NudgeStore does NOT exist
// (NudgeStore is app-target-only) — this intent cannot use toggleComplete. Instead it writes
// the completion straight to the per-item `reminders` table in Supabase, matching how the app
// syncs, so the app and other devices pick it up on their next sync.
//
// SCOPE / KNOWN LIMITATION (by design, agreed with Noah):
//   • Handles a plain one-off completion perfectly.
//   • Does NOT reproduce NudgeStore.toggleComplete's special cases: a RECURRING reminder's
//     next occurrence is NOT spawned here, and routines are not rolled forward. Those are
//     reconciled the next time the app opens and runs its own logic. For the common case
//     (ticking a normal reminder off the widget) this is exactly right.
//
// SYNC-COMPATIBILITY (important — why the write looks the way it does):
//   The app's per-item sync is last-write-wins on each row's `updated_at`. To avoid the app
//   clobbering this completion on its next sync, we (a) stamp `updated_at` with syncStamp(now),
//   which outranks the row's previous stamp, and (b) write back the FULL `data` JSON with only
//   the completion fields flipped — never a subset, or we'd wipe notes/recurrence/etc.
//
// SECURITY: anon key + the user's bearer token from the shared Keychain. RLS on the per-item
//   `reminders` table scopes the write to the signed-in user. No service-role key.

import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Small helper to ask WidgetKit to rebuild the Today widget's timeline.
enum WidgetReload {
    static func today() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "NudgeToday")
        #endif
    }
}

struct CompleteReminderWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Reminder (Widget)"
    static var description = IntentDescription("Mark a reminder complete from the widget without opening the app.")

    // The exact reminder id to complete. Passed by the widget Button(intent:).
    @Parameter(title: "Reminder ID") var reminderId: String

    init() {}
    init(reminderId: String) { self.reminderId = reminderId }

    func perform() async throws -> some IntentResult {
        await WidgetCompletion.complete(id: reminderId)
        return .result()
    }
}

/// The direct-to-Supabase completion write used by the widget tap intent.
enum WidgetCompletion {

    // Canonical stamp format the app's sync uses: ISO8601 with fractional seconds, UTC.
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Fetch the reminder's full row, flip its completion fields, and upsert it back with a
    /// fresh `updated_at`. Silently no-ops on any failure (no session, network, not found) —
    /// the widget will simply refresh from the server and still show the item, rather than
    /// pretending it completed.
    static func complete(id: String) async {
        guard let session = AuthStore.load() else { return }
        let now = Date()

        // 1) Read the row's FULL data payload (all keys, not just the widget subset), plus its
        //    id, so we can write everything back and only change the completion fields.
        guard var row = await fetchRow(id: id, token: session.accessToken) else { return }

        // 2) Flip completion fields in the raw JSON object.
        row["completed"] = .bool(true)
        row["completedAt"] = .string(stamp.string(from: now))
        // Clear any snooze so a completed item doesn't reappear when the snooze lapses.
        row["snoozedUntil"] = .null
        // Advance the item's own edit stamp too (kept in sync with the row's updated_at).
        row["updatedAt"] = .string(stamp.string(from: now))

        // 3) Upsert the whole row back with a fresh updated_at so the app's last-write-wins
        //    sync treats this completion as the newest state and doesn't clobber it.
        await upsert(id: id, data: row, updatedAt: stamp.string(from: now), token: session.accessToken)

        // 4) Nudge WidgetKit to rebuild so the item drops off immediately.
        WidgetReload.today()
    }

    // MARK: - Network

    private static func fetchRow(id: String, token: String) async -> [String: JSONVal]? {
        let path = "reminders?select=data&id=eq.\(id)&deleted_at=is.null&limit=1"
        guard let u = URL(string: "\(Secrets.supabaseURL)/rest/v1/\(path)") else { return nil }
        var req = URLRequest(url: u)
        req.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        // Response shape: [ { "data": { ...reminder... } } ]
        guard let arr = try? JSONDecoder().decode([RowWrap].self, from: data),
              let first = arr.first else { return nil }
        return first.data
    }

    private static func upsert(id: String, data: [String: JSONVal], updatedAt: String, token: String) async {
        guard let u = URL(string: "\(Secrets.supabaseURL)/rest/v1/reminders?on_conflict=user_id,id") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // merge-duplicates = update the existing row in place; return=minimal = no body back.
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let body = UpsertRow(id: id, data: data, updated_at: updatedAt)
        guard let payload = try? JSONEncoder().encode([body]) else { return }
        req.httpBody = payload
        _ = try? await URLSession.shared.data(for: req)
    }

    // Row shapes.
    private struct RowWrap: Decodable { let data: [String: JSONVal] }
    private struct UpsertRow: Encodable {
        let id: String
        let data: [String: JSONVal]
        let updated_at: String
    }
}

/// A minimal JSON value so we can round-trip a reminder's full `data` object without a
/// full Codable model in the widget target — we only need to flip a few keys and write it
/// back unchanged. Preserves all keys the widget doesn't understand.
enum JSONVal: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONVal])
    case array([JSONVal])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let o = try? c.decode([String: JSONVal].self) { self = .object(o); return }
        if let a = try? c.decode([JSONVal].self) { self = .array(a); return }
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
