// WidgetData.swift — Nudge widget extension
// Self-contained data layer for widgets: fetches the user's live reminders from the
// per-item Supabase tables (the same tables the app writes to since commit 5de79fb,
// "D1: per-item sync") and computes the stats each widget renders.
//
// HISTORY / WHY THIS CHANGED:
//   The widget used to read a single `nudge_data` blob. The app abandoned that table
//   when it moved to per-item sync, so `nudge_data` became a FROZEN snapshot — which is
//   why the widget kept showing old, already-completed reminders that were fine in the
//   app. The widget now reads the per-item `reminders` and `lists` tables directly, so
//   it always reflects the same live, RLS-protected data the app does.
//
// SECURITY: reads only the per-item tables, which have RLS live (each user sees only
//   their own rows). Uses the anon key + the user's bearer token from the shared
//   Keychain — exactly as before. No service-role key, no elevated access.

import Foundation
import SwiftUI

// Lightweight decode of just what widgets need (extra JSON keys are ignored).
struct WReminder: Codable {
    var id: String
    var title: String
    var dueDate: String?
    var hasTime: Bool?
    var listId: String?
    var priority: String?
    var completed: Bool?
    var completedAt: String?
    var snoozedUntil: String?
    var dismissed: Bool?
    var source: String?
}
struct WList: Codable { var id: String; var name: String; var color: String }
struct WData: Codable { var reminders: [WReminder]; var lists: [WList] }

/// One PostgREST row from a per-item table: `{ id, data, updated_at, deleted_at }`.
/// `data` holds the actual reminder/list JSON; a non-nil `deleted_at` is a tombstone
/// (the row exists only to propagate a delete) and MUST be skipped.
private struct WCloudRow<T: Codable>: Codable {
    var id: String
    var data: T?
    var deleted_at: String?
}

enum NudgeFeed {
    /// Reads the user's live reminders + lists from the per-item Supabase tables.
    /// Returns nil whenever it can't authenticate — signed out or an expired token —
    /// so the widget shows its "Can't sync" state rather than a false "All clear".
    /// The extension never refreshes tokens; the app does that the next time it opens.
    ///
    /// Note: reminders are the source of truth for the widget. If lists fail to load
    /// we still return the reminders (list colours just fall back to a default), so a
    /// hiccup on the lists table never blanks the whole widget.
    static func fetch() async -> WData? {
        guard let session = AuthStore.load() else { return nil }

        // Reminders are required. A nil here means a real auth/network failure → .failed.
        // Same hidden-source rule as NudgeStore: StudyTrack/Finance rows round-trip through
        // sync but are never shown in the app's own UI, so the widget must hide them too.
        guard let reminders = (await rows(table: "reminders", as: WReminder.self,
                                          token: session.accessToken))?
            .filter({ $0.source != "studytrack" && $0.source != "finance" }) else { return nil }

        // Lists are best-effort: nil (fetch failed) becomes an empty list rather than
        // failing the whole widget. Colours fall back to the default in the view.
        let lists = await rows(table: "lists", as: WList.self,
                               token: session.accessToken) ?? []

        return WData(reminders: reminders, lists: lists)
    }

    /// Pull every LIVE row from a per-item table (tombstones filtered out), returning the
    /// decoded `data` payloads. Returns nil only on a genuine request/auth failure so the
    /// caller can distinguish "couldn't sync" from "synced, nothing there".
    private static func rows<T: Codable>(table: String, as: T.Type, token: String) async -> [T]? {
        // Select only live rows (deleted_at IS NULL) and just the columns we decode.
        guard let u = URL(string: "\(Secrets.supabaseURL)/rest/v1/\(table)?select=id,data,deleted_at&deleted_at=is.null") else { return nil }
        var req = URLRequest(url: u)
        req.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        guard let decoded = try? JSONDecoder().decode([WCloudRow<T>].self, from: data) else { return nil }
        // Belt-and-braces: also drop any tombstone the query didn't filter, and any row
        // whose `data` failed to decode.
        return decoded.filter { $0.deleted_at == nil }.compactMap { $0.data }
    }
}

// MARK: - Date + text helpers (widget-local copies)

private let wIsoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private let wIsoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()
func wParseDate(_ s: String?) -> Date? {
    guard let s = s, !s.isEmpty else { return nil }
    return wIsoFrac.date(from: s) ?? wIsoPlain.date(from: s)
}
func wDisplay(_ title: String) -> String {
    let stripped = title.replacingOccurrences(of: "#[\\p{L}0-9_-]+", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    return stripped.isEmpty ? title : stripped
}
func wDueLabel(_ d: Date, hasTime: Bool) -> String {
    let cal = Calendar.current
    let f = DateFormatter()
    if cal.isDateInToday(d) { f.dateFormat = hasTime ? "HH:mm" : "'Today'" }
    else if cal.isDateInTomorrow(d) { f.dateFormat = hasTime ? "'Tmrw' HH:mm" : "'Tomorrow'" }
    else { f.dateFormat = hasTime ? "d MMM HH:mm" : "d MMM" }
    return f.string(from: d)
}

extension Color {
    init(wHex: String) {
        let h = wHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF)/255, green: Double((v >> 8) & 0xFF)/255, blue: Double(v & 0xFF)/255)
    }
}

enum WTheme {
    static let violet = Color(wHex: "5B4FCF")
    static let coral  = Color(wHex: "E85D4A")
    static let sage   = Color(wHex: "7CA982")
    static let grad   = LinearGradient(colors: [Color(wHex: "6E62E6"), Color(wHex: "5B4FCF")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let coralGrad = LinearGradient(colors: [Color(wHex: "F2745F"), Color(wHex: "E85D4A")],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
}
