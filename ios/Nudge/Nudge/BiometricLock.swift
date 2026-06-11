// BiometricLock.swift — Nudge
// Face ID / Touch ID (with passcode fallback) gate for opening the app.

import Foundation
import LocalAuthentication

enum BiometricLock {
    /// Is any device authentication available (biometrics or passcode)?
    static var available: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    /// Prompt for Face ID / Touch ID, falling back to the device passcode.
    /// Returns true if unavailable (so the user is never locked out).
    static func authenticate() async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Enter Passcode"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Nudge") { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
}
