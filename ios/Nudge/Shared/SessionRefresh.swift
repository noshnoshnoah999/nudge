// SessionRefresh.swift — refresh an expired Supabase session from EITHER target.
//
// WHY THIS EXISTS:
// The widget used to be unable to refresh its own token. `NudgeFeed.fetch()` just read whatever
// was in the Keychain, so once the access token lapsed (Supabase default ~1 hour) every widget
// request 401'd and the widget showed "Can't sync" until the app was next opened. `ensureSession()`
// lives in Nudge/Auth.swift, which is app-target-only, so the extension couldn't call it.
//
// That is precisely backwards for how Noah uses this. His whole setup is built to avoid opening
// apps — the widget IS the interface. A design that needs the app opened every hour to keep the
// widget alive breaks hardest exactly when it's working as intended.
//
// This file is in Shared/ so the widget extension can refresh too.
//
// ─────────────────────────────────────────────────────────────────────────────────────────────
// SAFETY — the important part. Supabase ROTATES refresh tokens: using one issues a new one and
// retires the old after a short reuse window. That makes a careless implementation dangerous,
// because two processes racing to refresh can invalidate each other and sign the user out.
//
// Three deliberate rules keep that from happening:
//
//   1. NEVER CLEAR THE SESSION ON FAILURE.
//      Nudge/Auth.swift `refreshSession()` treats 400/401 as terminal and calls
//      `AuthStore.clear()`. That is reasonable in the app, where the user is present and can
//      sign in again. It would be actively harmful here: a widget that loses a refresh race
//      would wipe a session that is still perfectly good, silently signing Noah out on a
//      background timeline build with no way to tell him why. So this refresher leaves the
//      Keychain untouched on every failure path and simply reports that it couldn't refresh.
//      Worst case the widget shows "Can't sync" for one cycle. That is a recoverable state;
//      being signed out is not.
//
//   2. ONE REFRESH AT A TIME, via a short Keychain lock.
//      Both targets read the session from the Keychain on every call (neither caches it in
//      memory — `Auth.bearer()` and `AuthStore.load()` both hit the Keychain), so whoever
//      refreshes first writes the new session and the other picks it up. The lock narrows the
//      window where both start a refresh at once.
//
//   3. ONLY REFRESH WHEN ACTUALLY STALE.
//      Gated on `Session.isFresh`, so a valid token is never spent for no reason. Fewer
//      rotations means fewer chances to race.
// ─────────────────────────────────────────────────────────────────────────────────────────────

import Foundation

enum SessionRefresh {

    /// Outcome of asking for a usable token.
    enum Result {
        case token(String)     // a usable access token (either already fresh, or just refreshed)
        case signedOut         // no session stored at all — the user must sign in
        case unavailable       // a session exists but couldn't be refreshed right now
    }

    /// A usable access token, refreshing first if the stored one has expired.
    ///
    /// Callers should branch on the result rather than treating every failure the same: a widget
    /// can say "Open Nudge to sign in" for `.signedOut` and "Can't sync" for `.unavailable`,
    /// which are very different problems for the user.
    static func accessToken() async -> Result {
        guard let session = AuthStore.load() else { return .signedOut }
        if session.isFresh { return .token(session.accessToken) }

        // Stale. Try to refresh — unless another process is already doing it, in which case
        // re-read the Keychain in case it has just landed.
        guard acquireLock() else {
            if let updated = AuthStore.load(), updated.isFresh { return .token(updated.accessToken) }
            return .unavailable
        }
        defer { releaseLock() }

        // Re-read after taking the lock: another process may have refreshed while we waited.
        if let updated = AuthStore.load(), updated.isFresh { return .token(updated.accessToken) }

        guard let refreshed = await performRefresh(refreshToken: session.refreshToken) else {
            return .unavailable
        }
        AuthStore.save(refreshed)
        return .token(refreshed.accessToken)
    }

    // MARK: - Network

    private struct TokenResponse: Codable {
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: User?
        struct User: Codable { var email: String? }
    }

    /// Mirrors `Nudge/Auth.swift`'s refresh call exactly — same endpoint, headers and body —
    /// EXCEPT that it never clears the session. See rule 1 at the top of this file.
    private static func performRefresh(refreshToken: String) async -> Session? {
        guard let url = URL(string: Secrets.supabaseURL + "/auth/v1/token?grant_type=refresh_token")
        else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0),
              let t = try? JSONDecoder().decode(TokenResponse.self, from: data)
        else { return nil }   // deliberately NOT clearing the session, even on 400/401

        return Session(accessToken: t.access_token,
                       refreshToken: t.refresh_token,
                       expiresAt: Date().addingTimeInterval(t.expires_in),
                       email: t.user?.email)
    }

    // MARK: - Cross-process lock
    //
    // A Keychain item in the shared access group, holding the time the lock was taken. Stale
    // locks expire so a process killed mid-refresh (very possible for a widget extension, which
    // the system suspends aggressively) can't block refreshes forever.

    private static let lockService = "uk.flouty.Nudge.sessionRefreshLock"
    private static let lockAccount = "lock"
    private static let accessGroup = "FMF6YAVA23.uk.flouty.Nudge.shared"
    private static let lockTimeout: TimeInterval = 20

    private static var lockQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: lockService,
         kSecAttrAccount as String: lockAccount,
         kSecAttrAccessGroup as String: accessGroup]
    }

    private static func acquireLock(now: Date = Date()) -> Bool {
        if let held = lockTakenAt(), now.timeIntervalSince(held) < lockTimeout { return false }
        guard let data = try? JSONEncoder().encode(now) else { return false }
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(lockQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = lockQuery
            add.merge(attrs) { a, _ in a }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func lockTakenAt() -> Date? {
        var q = lockQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    private static func releaseLock() {
        SecItemDelete(lockQuery as CFDictionary)
    }
}
