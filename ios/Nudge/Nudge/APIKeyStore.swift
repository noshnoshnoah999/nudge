// APIKeyStore.swift — Nudge (iOS)
// The Anthropic API key, stored in the Keychain instead of UserDefaults.
//
// WHY: the Anthropic key is a real billing secret. UserDefaults is plaintext and is
// copied into device/iCloud backups, so it is the wrong place for it. The Keychain is
// encrypted and hardware-protected. This mirrors AuthStore.swift, which already keeps the
// Supabase session tokens in the Keychain for the same reason.
//
// NOTE: unlike AuthStore this deliberately does NOT set an access group — only the main app
// needs the key (the widget never calls Anthropic), so it stays in the app's private
// Keychain. `WhenUnlockedThisDeviceOnly` keeps it off backups and off other devices entirely.
//
// MIGRATION: `migrateFromUserDefaultsIfNeeded()` runs once at launch. If a key was previously
// saved in UserDefaults (any build before this change), it is copied into the Keychain and the
// plaintext copy is deleted, so existing users never have to re-enter their key and no
// plaintext copy is left behind.

import Foundation

enum APIKeyStore {
    private static let service = "uk.flouty.Nudge.anthropic"
    private static let account = "anthropic-api-key"
    /// The old UserDefaults key this used to live under (now migrated away from).
    private static let legacyDefaultsKey = "anthropic_api_key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The stored key, or "" if none. "" is treated the same as "no key" by every caller.
    static func load() -> String {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    /// Save (or clear, if empty) the key. Empty string deletes the Keychain item so an
    /// emptied Settings field doesn't leave a stale key behind.
    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clear(); return }
        guard let data = trimmed.data(using: .utf8) else { return }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            // ThisDeviceOnly = never leaves this device via backup/restore; the user re-enters
            // it on a new phone. Correct for a billing secret.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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

    static var hasKey: Bool { !load().isEmpty }

    /// One-time move of any plaintext key from UserDefaults into the Keychain. Safe to call on
    /// every launch: it only acts if a legacy value is present, and it deletes the plaintext
    /// copy afterwards so it can't be read from a backup. If a Keychain key already exists we
    /// still delete the stale UserDefaults copy (defensive — never leave plaintext around).
    static func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: legacyDefaultsKey), !legacy.isEmpty else { return }
        if !hasKey { save(legacy) }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
