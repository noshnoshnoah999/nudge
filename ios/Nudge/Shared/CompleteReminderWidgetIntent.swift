// CompleteReminderWidgetIntent.swift — Nudge (shared: app + widget extension)
//
// The App Intent run by a tap on a reminder row in the Today widget. Because a widget
// Button(intent:) runs in the WIDGET'S process — where the app's NudgeStore does NOT exist
// (NudgeStore is app-target-only) — this intent cannot use toggleComplete. Instead it writes
// the completion straight to the per-item `reminders` table in Supabase, matching how the app
// syncs, so the app and other devices pick it up on their next sync.
//
// SCOPE — completing from the widget now matches completing in the app:
//   • One-off        → marked completed. (Always worked.)
//   • Repeating      → this occurrence completes AND the next one is spawned.
//   • Nightly routine→ never "completes": a history snapshot is written and the routine
//                      rolls forward to its next night, escalation phases honoured.
//   The dates come from RecurrenceEngine (Shared/), the same code NudgeStore uses, so the
//   two paths cannot disagree.
//
// FIXED 2026-08-05 — the bug this replaces:
//   This file used to just set completed = true regardless of the item's type, and its own
//   header claimed the app would "reconcile" routines and recurrences on next launch. No such
//   reconcile ever existed for this path (the only one, in RemindersSync, covers items ticked
//   in APPLE Reminders, not Supabase writes). So on 2026-08-04 Noah ticked "Epiduo Night" and
//   "KP Body Scrub Night" off the widget and both routines died on the spot, as if they had
//   been one-off tasks. Never trust that comment's successor: if a rule lives in NudgeStore,
//   it must live in Shared/ or it does not apply here.
//
// TWO THINGS THE WIDGET STILL CANNOT DO, both self-healing on next app launch:
//   • Schedule the new occurrence's local notification. An extension's UNUserNotificationCenter
//     is its own, not the app's. NotificationManager.reschedule() rebuilds everything from the
//     store when the app next syncs.
//   • Move a linked "prep" reminder (e.g. Buy Ginger Shot Ingredients → Make Ginger Shots).
//     NudgeStore.refresh() calls syncPrepReminders() after every pull.
//
// WRITE ORDER IS DELIBERATE — the new row goes up FIRST, the completion second, and the
// completion is skipped entirely if the first write fails. A half-finished completion must
// never be the one that ends a series: worst case here is a duplicate open occurrence, which
// is visible and fixable, rather than a routine that silently stops forever.
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
///
/// `nonisolated` for the same reason as WidgetPendingCompletionStore: the project builds with
/// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, which would pin `today()` to the main actor and
/// make it unreachable from the non-isolated `perform()` below. `WidgetCenter.shared` is
/// documented as safe to call from any thread, so there is nothing to protect here.
nonisolated enum WidgetReload {
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

    /// TWO-TAP CONFIRMATION — first tap arms the row, second tap completes it.
    ///
    /// A widget cannot show a confirmation dialog: `requestConfirmation()` is ignored when an
    /// AppIntent is run from a widget `Button(intent:)` (Apple Developer Forums 732037, 732904).
    /// So the confirmation is the second tap. See WidgetPendingCompletionStore for the state and
    /// the expiry behaviour.
    ///
    /// Deliberately fails safe: anything unexpected (expired arm, a different row armed, no
    /// stored state) falls through to ARMING rather than completing. A stray tap can therefore
    /// never complete a reminder on its own.
    func perform() async throws -> some IntentResult {
        if let pending = WidgetPendingCompletionStore.current(), pending.id == reminderId {
            // Confirmed — this exact row was armed and the window hasn't lapsed.
            WidgetPendingCompletionStore.clear()
            await WidgetCompletion.complete(id: reminderId)
        } else {
            // First tap on this row (or the armed row was a different one / had expired).
            // Arm it and re-render so the row visibly asks for a second tap. Nothing is written
            // to Supabase in this branch.
            WidgetPendingCompletionStore.arm(id: reminderId)
            WidgetReload.today()
        }
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

    /// Complete a reminder the way the app would, whatever kind it is.
    ///
    /// Silently no-ops on any failure (no session, network, row not found) — the widget then
    /// simply refreshes from the server and still shows the item, rather than pretending it
    /// completed.
    static func complete(id: String) async {
        // Refresh the token first if it's stale. Previously this read the Keychain directly, so a
        // tap made with an expired access token silently no-op'd: the row fetch 401'd, the guard
        // below returned, and the reminder just stayed put with no explanation. Same root cause as
        // the widget's "Can't sync" — see SessionRefresh.
        guard case .token(let token) = await SessionRefresh.accessToken() else { return }
        let now = Date()
        let nowStamp = stamp.string(from: now)

        // Read the row's FULL data payload (all keys, not just the widget subset) so we can
        // write everything back and change only what completing it should change.
        guard var row = await fetchRow(id: id, token: token) else { return }

        let rule = engineRule(from: row["recurrence"])
        let isRoutine = (row["routine"]?.boolValue ?? false)

        switch RecurrenceEngine.completionKind(isRoutine: isRoutine, rule: rule) {

        // ── Nightly routine (Epiduo, KP Body Scrub, Make Ginger Shots) ──────────────────
        // Mirrors NudgeStore.routineDidIt: leave a "done on this night" record in history,
        // then roll the routine itself forward, still open.
        case .routine:
            // Anchor on the night it was DUE, not on now, so ticking a lapsed routine
            // schedules the same next date the morning check-in would.
            let night = RecurrenceEngine.parse(row["dueDate"]?.stringValue) ?? now

            // 1) History snapshot — a one-off, completed clone of this occurrence.
            //    Mirrors NudgeStore.completedSnapshot field for field.
            let snapId = newReminderId()
            var snap = row
            snap["id"] = .string(snapId)
            snap["completed"] = .bool(true)
            snap["completedAt"] = .string(nowStamp)
            snap["dueDate"] = .string(stamp.string(from: night))
            snap["recurrence"] = .null
            snap["routine"] = .bool(false)
            snap["escalation"] = .null
            snap["snoozedUntil"] = .null
            snap["pinned"] = .bool(false)
            snap["createdAt"] = .string(nowStamp)
            snap["updatedAt"] = .string(nowStamp)
            // Fail safe: if history can't be written, leave the routine completely untouched
            // rather than advancing it with no record that it was done.
            guard await upsert(id: snapId, data: snap, updatedAt: nowStamp, token: token) else { return }

            // 2) Roll the routine forward. Stays open; completedAt is nil because the
            //    snapshot above is now the completion record (no double-count in Done-today).
            row["dueDate"] = .string(RecurrenceEngine.advancedRoutineDue(
                night: night,
                currentDue: row["dueDate"]?.stringValue,
                escalation: enginePhases(from: row["escalation"]),
                rule: rule,
                now: now))
            row["completed"] = .bool(false)
            row["completedAt"] = .null
            row["snoozedUntil"] = .null
            row["updatedAt"] = .string(nowStamp)
            _ = await upsert(id: id, data: row, updatedAt: nowStamp, token: token)

        // ── Plain repeating reminder ────────────────────────────────────────────────────
        // Mirrors NudgeStore.toggleComplete: this occurrence completes and becomes history,
        // and the next one is spawned as a new open row.
        case .repeating:
            if let rule,
               let next = RecurrenceEngine.nextOccurrence(afterDue: row["dueDate"]?.stringValue,
                                                          rule: rule,
                                                          now: now) {
                let copyId = newReminderId()
                var copy = row
                copy["id"] = .string(copyId)
                copy["completed"] = .bool(false)
                copy["completedAt"] = .null
                copy["snoozedUntil"] = .null
                copy["dueDate"] = .string(next)
                copy["createdAt"] = .string(nowStamp)
                copy["updatedAt"] = .string(nowStamp)
                // Fail safe: no successor written → do not complete this one, or the series
                // ends here. That is exactly the bug this whole change exists to fix.
                guard await upsert(id: copyId, data: copy, updatedAt: nowStamp, token: token) else { return }
            }
            // No `next` means the series has passed its end-repeat date — completing it
            // outright is correct, and is what the app does too.
            await markCompleted(id: id, row: &row, nowStamp: nowStamp, token: token)

        // ── Ordinary one-off ────────────────────────────────────────────────────────────
        case .oneOff:
            await markCompleted(id: id, row: &row, nowStamp: nowStamp, token: token)
        }

        // Rebuild the timeline so the item drops off (or reappears at its new date) at once.
        WidgetReload.today()
    }

    /// Flip a row's completion fields and upsert it back with a fresh `updated_at`, so the
    /// app's last-write-wins sync treats this completion as the newest state.
    private static func markCompleted(id: String, row: inout [String: JSONVal],
                                      nowStamp: String, token: String) async {
        row["completed"] = .bool(true)
        row["completedAt"] = .string(nowStamp)
        // Clear any snooze so a completed item doesn't reappear when the snooze lapses.
        row["snoozedUntil"] = .null
        // Advance the item's own edit stamp too (kept in sync with the row's updated_at).
        row["updatedAt"] = .string(nowStamp)
        _ = await upsert(id: id, data: row, updatedAt: nowStamp, token: token)
    }

    /// Same id shape the app generates (NudgeStore uses "r" + 12 UUID chars).
    private static func newReminderId() -> String {
        "r" + String(UUID().uuidString.prefix(12))
    }

    // MARK: - JSON → RecurrenceEngine

    /// Build the engine's rule from the row's raw `recurrence` object. Returns nil when the
    /// key is absent, null, or has no `freq` — all of which mean "does not repeat".
    private static func engineRule(from value: JSONVal?) -> RecurrenceEngine.Rule? {
        guard case .object(let o)? = value, let freq = o["freq"]?.stringValue else { return nil }
        return RecurrenceEngine.Rule(freq: freq,
                                     interval: o["interval"]?.intValue,
                                     until: o["until"]?.stringValue)
    }

    /// Build the engine's escalation phases from the row's raw `escalation` array.
    /// Order is preserved — the engine walks the phases in sequence to find the active one.
    private static func enginePhases(from value: JSONVal?) -> [RecurrenceEngine.EscalationPhase]? {
        guard case .array(let items)? = value, !items.isEmpty else { return nil }
        let phases: [RecurrenceEngine.EscalationPhase] = items.compactMap { item in
            guard case .object(let o) = item, let days = o["everyDays"]?.intValue else { return nil }
            return RecurrenceEngine.EscalationPhase(everyDays: days, until: o["until"]?.stringValue)
        }
        return phases.isEmpty ? nil : phases
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

    /// Returns true only on a 2xx. Callers chain writes on this: a completion is never sent
    /// when the row that keeps the series alive failed to go up. `user_id` is deliberately
    /// not sent — the column defaults to auth.uid() and RLS pins it, so a row inserted here
    /// lands on the signed-in user exactly as one written by the app does.
    @discardableResult
    private static func upsert(id: String, data: [String: JSONVal], updatedAt: String, token: String) async -> Bool {
        guard let u = URL(string: "\(Secrets.supabaseURL)/rest/v1/reminders?on_conflict=user_id,id") else { return false }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // merge-duplicates = update the existing row in place; return=minimal = no body back.
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let body = UpsertRow(id: id, data: data, updated_at: updatedAt)
        guard let payload = try? JSONEncoder().encode([body]) else { return false }
        req.httpBody = payload
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0)
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

    // MARK: - Typed reads
    // Used to pull `recurrence` / `escalation` / `routine` / `dueDate` out of a reminder's
    // raw JSON so RecurrenceEngine can work on them. Each returns nil for the wrong shape —
    // never a default — so a malformed field makes the item fall through to a plain
    // completion rather than being rolled forward to a made-up date.

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    /// Ints arrive as JSON numbers; `interval` and `everyDays` are always whole.
    var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
}
