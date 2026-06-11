// SplashView.swift — Nudge (iOS)
// A ~3-second branded launch screen: a "ping" bell that rings while concentric
// ripples radiate outward (the nudge), with the wordmark + tagline animating in
// and a trio of pulsing loader dots. Fades into the app via RootContainer.

import SwiftUI

/// Wraps the app so a splash plays once per cold launch, then fades into
/// ContentView. Environment objects applied here propagate down to ContentView.
struct RootContainer: View {
    // Shown only the first time the view appears in this process. Returning from
    // the background reuses the same process (and an already-shown flag), so the
    // splash does not replay; a true cold start resets the flag and shows it again.
    @MainActor static var hasShownSplash = false
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
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // ~2s
            withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
        }
    }
}

struct SplashView: View {
    @State private var ripple = false   // concentric rings radiating out
    @State private var pop    = false   // bell disc scales in
    @State private var ring   = false   // bell wiggle ("ringing")
    @State private var textIn = false   // wordmark
    @State private var tagIn  = false   // tagline
    @State private var dots   = false   // loader dots

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            // Radiating "ping" ripples behind the bell.
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.accent.opacity(0.30), lineWidth: 2)
                        .frame(width: 130, height: 130)
                        .scaleEffect(ripple ? 2.7 : 0.45)
                        .opacity(ripple ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 1.9)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.63),
                            value: ripple)
                }
            }

            VStack(spacing: 22) {
                // Bell disc — scales in with a spring, then rings.
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 96, height: 96)
                        .cardElevation(20, y: 8, opacity: 0.22)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(ring ? 9 : -9), anchor: .top)
                }
                .scaleEffect(pop ? 1 : 0.55)
                .opacity(pop ? 1 : 0)

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

            // Loader dots near the bottom.
            VStack {
                Spacer()
                HStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                            .scaleEffect(dots ? 1 : 0.5)
                            .opacity(dots ? 1 : 0.35)
                            .animation(
                                .easeInOut(duration: 0.55)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.18),
                                value: dots)
                    }
                }
                .padding(.bottom, 54)
            }
        }
        .onAppear { runSequence() }
    }

    private func runSequence() {
        ripple = true
        dots = true
        withAnimation(Theme.bouncy) { pop = true }
        // Bell rings: a few quick wiggles shortly after it lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.11).repeatCount(7, autoreverses: true)) { ring = true }
        }
        withAnimation(Theme.spring.delay(0.40)) { textIn = true }
        withAnimation(Theme.spring.delay(0.72)) { tagIn = true }
    }
}
