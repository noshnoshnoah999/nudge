// WidgetData.swift — Nudge widget extension
// Self-contained data layer for widgets: fetches the same Supabase blob the app
// uses (no App Group needed) and computes the stats each widget renders.

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
}
struct WList: Codable { var id: String; var name: String; var color: String }
struct WData: Codable { var reminders: [WReminder]; var lists: [WList] }
private struct WRow: Codable { var data: WData }

enum NudgeFeed {
    /// Reads the session the app wrote to the shared Keychain group. Returns nil
    /// whenever it can't authenticate — signed out, or an expired token — so the
    /// widget keeps its last rendered state rather than blanking. The extension
    /// never refreshes tokens; the app does that the next time it opens.
    static func fetch() async -> WData? {
        guard let session = AuthStore.load(),
              let u = URL(string: "\(Secrets.supabaseURL)/rest/v1/nudge_data?select=data") else { return nil }
        var req = URLRequest(url: u)
        req.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return nil }
        return (try? JSONDecoder().decode([WRow].self, from: data))?.first?.data
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
