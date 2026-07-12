// SplashView.swift — Nudge (iOS)
// A short, lightweight branded launch screen that matches the app icon: the
// concentric-ring "nudge" mark radiates outward from the center (center dot →
// inner ring → outer ring), followed by the wordmark + tagline. Fades into the
// app via RootContainer.
//
// Deliberately avoids any `repeatForever` animations: the splash only holds for
// ~1.3s, so every animation here is a one-shot transition. This keeps the launch
// smooth (no continuously running layers churning while the app boots).

import SwiftUI

/// Wraps the app so a splash plays once per cold launch, then fades into
/// ContentView. Environment objects applied here propagate down to ContentView.
struct RootContainer: View {
    // Shown only the first time the view appears in this process. Returning from
    // the background reuses the same process (and an already-shown flag), so the
    // splash does not replay; a true cold start resets the flag and shows it again.
    @MainActor static var hasShownSplash = false

    // True once the splash has fully dismissed on this cold launch. ContentView
    // waits on this before presenting the Face ID lock, so the splash and the
    // lock never render on top of each other (the old cause of the "lock for 1s,
    // then a leftover animation" jank). When app-lock is OFF this still flips
    // true, so nothing else waits on it. Starts true when there's no splash to
    // show (warm relaunch) so the lock isn't held up.
    @MainActor static var splashFinished = RootContainer.hasShownSplash

    @State private var showSplash = !RootContainer.hasShownSplash

    var body: some View {
        ZStack {
            ContentView()
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showSplash else { return }
            RootContainer.hasShownSplash = true
            // Hold long enough for the radiate-in to read fully before the Face ID
            // prompt that follows it.
            try? await Task.sleep(nanoseconds: 1_800_000_000)   // ~1.8s hold (≈2.1s incl. fade)
            withAnimation(.easeInOut(duration: 0.3)) { showSplash = false }
            // Splash is dismissing — release the lock gate so Face ID can present
            // cleanly, with no overlap.
            RootContainer.splashFinished = true
        }
    }
}

struct SplashView: View {
    // Each ring of the logo mark scales/fades in one after another, radiating out
    // from the center. All one-shot — no forever loops.
    @State private var centerIn = false   // solid center dot
    @State private var innerIn  = false   // inner (cream) ring
    @State private var outerIn  = false   // outer (tan) ring
    @State private var pulse    = false   // single outward "nudge" ripple
    @State private var textIn   = false   // wordmark
    @State private var tagIn    = false   // tagline

    // Sizes tuned to echo the app-icon proportions.
    private let outerSize: CGFloat = 132
    private let innerSize: CGFloat = 84
    private let centerSize: CGFloat = 34

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 26) {
                // Concentric-ring mark — matches the app icon.
                ZStack {
                    // A single soft ripple that expands out past the mark once,
                    // reinforcing the "radiate outward" motion.
                    Circle()
                        .stroke(Theme.accent.opacity(0.25), lineWidth: 2)
                        .frame(width: outerSize, height: outerSize)
                        .scaleEffect(pulse ? 1.8 : 0.9)
                        .opacity(pulse ? 0 : 0.6)

                    // Outer ring (fainter / tan-like) — appears last.
                    Circle()
                        .stroke(Theme.accent.opacity(0.55), lineWidth: 6)
                        .frame(width: outerSize, height: outerSize)
                        .scaleEffect(outerIn ? 1 : 0.4)
                        .opacity(outerIn ? 1 : 0)

                    // Inner ring (solid cream/accent) — appears second.
                    Circle()
                        .stroke(Theme.accent, lineWidth: 12)
                        .frame(width: innerSize, height: innerSize)
                        .scaleEffect(innerIn ? 1 : 0.4)
                        .opacity(innerIn ? 1 : 0)

                    // Center dot — pops in first.
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: centerSize, height: centerSize)
                        .scaleEffect(centerIn ? 1 : 0.2)
                        .opacity(centerIn ? 1 : 0)
                }
                .frame(width: outerSize, height: outerSize)
                .cardElevation(20, y: 8, opacity: 0.18)

                VStack(spacing: 7) {
                    Text("Nudge")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textMain)
                        .opacity(textIn ? 1 : 0)
                        .offset(y: textIn ? 0 : 14)
                    Text("reminders that don't get forgotten")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textMeta)
                        .opacity(tagIn ? 1 : 0)
                        .offset(y: tagIn ? 0 : 8)
                }
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // Radiate outward: center → inner ring → outer ring, each a quick spring.
        withAnimation(Theme.bouncy)                 { centerIn = true }
        withAnimation(Theme.spring.delay(0.12))     { innerIn  = true }
        withAnimation(Theme.spring.delay(0.24))     { outerIn  = true }
        // One soft ripple out, in sync with the rings landing.
        withAnimation(.easeOut(duration: 0.9).delay(0.24)) { pulse = true }
        // Wordmark + tagline follow.
        withAnimation(Theme.spring.delay(0.42))     { textIn = true }
        withAnimation(Theme.spring.delay(0.60))     { tagIn  = true }
    }
}
