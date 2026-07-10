// Auth.swift — Supabase email OTP sign-in for the iOS/Catalyst app.
//
// Uses the 6-digit emailed CODE flow rather than magic links: a link needs a
// Universal Link / custom scheme round-trip, a code needs nothing. The web app
// (index.html) uses magic links because a browser can just follow the redirect.
import Foundation

enum Auth {
    enum AuthError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self {
            case .server(let m): return m
            }
        }
    }

    private static func request(_ path: String, body: [String: Any]) -> URLRequest? {
        guard let u = URL(string: Secrets.supabaseURL + path) else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    /// Supabase surfaces failures as {"error_description": ...} or {"msg": ...}.
    private static func errorMessage(_ data: Data, status: Int) -> String {
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in ["error_description", "msg", "message", "error"] {
                if let s = j[k] as? String { return s }
            }
        }
        return "Sign-in failed (HTTP \(status))."
    }

    /// Emails a 6-digit code. Supabase rate-limits this hard (~2/hour on free tier).
    static func sendCode(email: String) async throws {
        guard let req = request("/auth/v1/otp", body: ["email": email, "create_user": true]) else { return }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw AuthError.server(code == 429
                ? "Too many requests — Supabase limits code emails to about two per hour. Wait, then try again."
                : errorMessage(data, status: code))
        }
    }

    private struct TokenResponse: Codable {
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: User?
        struct User: Codable { var email: String? }
    }

    private static func store(_ t: TokenResponse) {
        AuthStore.save(Session(accessToken: t.access_token,
                               refreshToken: t.refresh_token,
                               expiresAt: Date().addingTimeInterval(t.expires_in),
                               email: t.user?.email))
    }

    static func verifyCode(email: String, token: String) async throws {
        guard let req = request("/auth/v1/verify",
                                body: ["type": "email", "email": email, "token": token]) else { return }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw AuthError.server(errorMessage(data, status: code)) }
        store(try JSONDecoder().decode(TokenResponse.self, from: data))
    }

    /// Swaps the refresh token for a new session. A rejected refresh token is
    /// terminal — clear the session so the app falls back to local-only rather
    /// than retrying a token the server will never accept.
    @discardableResult
    static func refreshSession() async -> Bool {
        guard let s = AuthStore.load(),
              let req = request("/auth/v1/token?grant_type=refresh_token",
                                body: ["refresh_token": s.refreshToken]) else { return false }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return false }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 { AuthStore.clear(); return false }
        guard (200..<300).contains(code),
              let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else { return false }
        store(t)
        return true
    }

    /// True when we hold a token good for the next request.
    static func ensureSession() async -> Bool {
        guard let s = AuthStore.load() else { return false }
        if s.isFresh { return true }
        return await refreshSession()
    }

    /// Falls back to the anon key so unauthenticated requests are well-formed;
    /// RLS returns [] for them rather than erroring.
    static func bearer() -> String {
        AuthStore.load()?.accessToken ?? Secrets.supabaseAnon
    }
}
