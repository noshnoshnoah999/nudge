// AuthStore.swift — the Supabase session, shared between the app and the widget.
//
// Lives in the Keychain rather than UserDefaults because it holds bearer tokens.
// The access group is what lets the widget extension read a session the app wrote;
// there is no App Group on this project (free team), so the Keychain is the only
// shared store available to both targets.
import Foundation

struct Session: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String?

    /// Treat a token that expires within the minute as already dead — a request
    /// started now would otherwise land after expiry.
    var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

enum AuthStore {
    private static let service = "uk.flouty.Nudge.session"
    private static let account = "supabase"
    private static let accessGroup = "FMF6YAVA23.uk.flouty.Nudge.shared"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: accessGroup]
    }

    static func load() -> Session? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ s: Session) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        // AfterFirstUnlock so the widget can still read the session on a locked
        // device — widgets refresh their timelines without the user unlocking.
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

    /// A session exists. Says nothing about whether the token is still valid —
    /// callers that are about to hit the network want `ensureSession()` instead.
    static var isAuthed: Bool { load() != nil }
}
