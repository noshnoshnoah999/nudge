// WidgetPendingCompletionStore.swift — the "are you sure?" state for widget tap-to-complete.
//
// WHY THIS EXISTS:
// A tap on a Today-widget row used to complete a reminder instantly, with no confirmation and
// no undo — one stray tap while rearranging the Home Screen silently ticked something off.
//
// WHY IT ISN'T A SYSTEM CONFIRMATION DIALOG:
// `AppIntent.requestConfirmation()` does NOT work from a widget `Button(intent:)`. It's a known
// WidgetKit limitation — the intent's `perform()` just runs and the confirmation is ignored
// (Apple Developer Forums 732037, 732904). Widgets cannot present UI. So confirmation has to be
// built out of the only interaction a widget actually has: another tap.
//
// THE PATTERN — tap once to arm, tap the same row again to confirm:
//   1st tap  → store {id, armedAt} here, reload the timeline. That row now renders struck
//              through with "tap again", so it's clear nothing has happened yet.
//   2nd tap  → if it's the same id and still inside `window`, complete it for real.
//   Tap a different row while one is armed → that row arms instead; the first is forgotten.
//   No second tap → the timeline carries an entry at `armedAt + window` (10s) that clears the
//              armed look automatically, so it can't sit armed forever.
//
// WHY THE KEYCHAIN rather than the widget's own UserDefaults:
// iOS does not firmly guarantee which process performs a widget's intent — there are reports of
// it being routed to the containing app when the app is running (Apple Developer Forums 732771).
// UserDefaults.standard would then be a different store than the timeline provider reads, and
// the arm/confirm handshake would break. The shared Keychain access group is readable from both
// the app and the extension, so the handshake holds either way. It's the same access group
// already used for the session (AuthStore) — no App Group needed, which matters on a free team.
//
// This is UI state, not a secret. It's in the Keychain for reachability, not for protection.

import Foundation

struct PendingCompletion: Codable, Equatable {
    let id: String
    let armedAt: Date
}

enum WidgetPendingCompletionStore {
    private static let service = "uk.flouty.Nudge.widgetPendingCompletion"
    private static let account = "today"
    private static let accessGroup = "FMF6YAVA23.uk.flouty.Nudge.shared"

    /// How long an armed row stays armed. Long enough to be a deliberate second tap, short
    /// enough that a forgotten arm doesn't linger and get confirmed by accident much later.
    /// Noah's choice: 10 seconds.
    static let window: TimeInterval = 10

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: accessGroup]
    }

    /// The currently armed reminder, or nil if nothing is armed or the window has lapsed.
    /// Expired state is treated as absent rather than being deleted here — reads happen during
    /// timeline building and should stay side-effect free.
    static func current(now: Date = Date()) -> PendingCompletion? {
        guard let p = raw() else { return nil }
        return now.timeIntervalSince(p.armedAt) < window ? p : nil
    }

    private static func raw() -> PendingCompletion? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(PendingCompletion.self, from: data)
    }

    static func arm(id: String, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(PendingCompletion(id: id, armedAt: now)) else { return }
        // AfterFirstUnlock to match AuthStore — widget timelines rebuild on a locked device.
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attrs) { a, _ in a }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// When the currently armed row should stop looking armed. Nil if nothing is armed.
    /// Used to schedule a timeline entry that disarms it visually.
    static func expiry(now: Date = Date()) -> Date? {
        guard let p = current(now: now) else { return nil }
        return p.armedAt.addingTimeInterval(window)
    }
}
