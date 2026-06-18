// LockShield.swift — Nudge (iOS)
// A privacy/lock cover that lives in its own UIWindow above EVERYTHING — including
// presented sheets and the app-switcher snapshot. A plain SwiftUI `.overlay` can't
// do this (sheets render above overlays), which is why an open "New reminder" sheet
// used to stay visible behind Face ID on resume. This window fixes that leak.

import SwiftUI
import UIKit

@MainActor
final class LockShield {
    static let shared = LockShield()
    private var window: UIWindow?
    private var shownInteractive: Bool?   // current visible state, nil = hidden
    /// Called when the user taps Unlock on the interactive shield.
    var onUnlock: (() -> Void)?

    /// Show the cover. `interactive` adds the lock glyph + Unlock button; otherwise
    /// it's just a blur (used for the brief app-switcher snapshot).
    func show(interactive: Bool) {
        // Already showing this exact state — don't rebuild it (avoids flicker when
        // scenePhase .active fires repeatedly under Stage Manager).
        if shownInteractive == interactive, let w = window, !w.isHidden { return }
        shownInteractive = interactive
        guard let scene = activeScene() else { return }
        if window == nil {
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            w.backgroundColor = .clear
            window = w
        }
        let host = UIHostingController(
            rootView: LockShieldView(interactive: interactive) { [weak self] in self?.onUnlock?() })
        host.view.backgroundColor = .clear
        window?.rootViewController = host
        window?.isHidden = false
    }

    func hide() {
        window?.isHidden = true
        window = nil
        shownInteractive = nil
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }
}

private struct LockShieldView: View {
    let interactive: Bool
    var onUnlock: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Theme.bg.opacity(0.5).ignoresSafeArea()
            if interactive {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(Theme.accent).frame(width: 84, height: 84)
                        Image(systemName: "lock.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
                    }
                    Text("Nudge is locked").font(.title3.weight(.bold)).foregroundStyle(Theme.textMain)
                    Button { onUnlock() } label: {
                        Label("Unlock", systemImage: "faceid")
                            .font(.headline).foregroundStyle(.white)
                            .padding(.horizontal, 24).padding(.vertical, 13)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}
