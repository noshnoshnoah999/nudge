// SplashView.swift — Nudge (iOS)
// The branded launch animation (concentric-ring mark + wordmark) was removed on
// 2026-07-22 at Noah's request: the app now goes straight to ContentView on
// launch, with no intro screen.
//
// RootContainer is kept as a thin pass-through (rather than deleted outright) so
// NudgeApp.swift's `RootContainer()` call site, and ContentView's `splashFinished`
// gate that sequences Face ID, don't need to change. `splashFinished` is always
// true now — there is nothing to wait for — so ContentView's poll loop around it
// resolves instantly and Face ID fires as soon as the window is ready.
//
// SplashView itself is left below, unused, in case a future launch animation is
// wanted again — it is not referenced anywhere.

import SwiftUI

struct RootContainer: View {
    @MainActor static var splashFinished = true

    var body: some View {
        ContentView()
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
