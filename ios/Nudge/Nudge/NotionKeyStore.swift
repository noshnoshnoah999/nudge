// NotionKeyStore.swift — Nudge (iOS)
// The Notion internal-integration token and target database ID, stored in the Keychain.
//
// WHY: the Notion token is a real secret — anyone holding it can read/write everything the
// integration has been shared with. UserDefaults is plaintext and gets copied into
// device/iCloud backups, so it's the wrong place for it. This mirrors APIKeyStore.swift
// (the Anthropic key), which already made this exact call for the same reason.
//
// The database ID is NOT secret (it's just a workspace-internal identifier, useless without
// the token), but it's kept alongside the token here for simplicity and because it's tied to
// the same "Notion set up?" on/off state as the token.
//
// NOTE: like APIKeyStore, no access group is set — only the main app pushes to Notion (the
// widget never does), so this stays in the app's private Keychain.
// `WhenUnlockedThisDeviceOnly` keeps it off backups and off other devices entirely; on a new
// device the user re-enters it via Settings, same as the Anthropic key.

import Foundation

enum NotionKeyStore {
    private static let service = "uk.flouty.Nudge.notion"
    private static let tokenAccount = "notion-integration-token"
    private static let databaseIdAccount = "notion-todo-database-id"

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func load(_ account: String) -> String {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Save (or clear, if empty) a value. Empty string deletes the Keychain item so an
    /// emptied Settings field doesn't leave a stale value behind.
    private static func save(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = baseQuery(account)
        guard !trimmed.isEmpty else { SecItemDelete(query as CFDictionary); return }
        guard let data = trimmed.data(using: .utf8) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attrs) { a, _ in a }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static var token: String {
        get { load(tokenAccount) }
        set { save(newValue, account: tokenAccount) }
    }

    static var databaseId: String {
        get { load(databaseIdAccount) }
        set { save(newValue, account: databaseIdAccount) }
    }

    /// Both a token and a database ID are required before the push button can do anything.
    static var isConfigured: Bool { !token.isEmpty && !databaseId.isEmpty }
}
