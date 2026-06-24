// CelebrationView.swift — Nudge (iOS)
// The reward animation played when a reminder is completed (Option C): the task glows gold,
// a checkmark lifts and dissolves into sparkles that float up and fade, with a gentle chime
// and a soft haptic. Calm and premium — "a weight lifted". ~1.3s.
// The haptic + chime are gated by AppSettings.celebrationFeedback (Settings toggle).

import SwiftUI
import AudioToolbox

/// Published by NudgeStore each time a reminder is ticked off.
struct CelebrationEvent: Identifiable, Equatable {
    let id: UUID
    let streak: Int
}

/// Full-screen, non-interactive overlay. Plays once, then calls `onDone`.
struct CelebrationOverlay: View {
    let event: CelebrationEvent
    var onDone: () -> Void

    @AppStorage("pref.celebrationFeedback") private var feedback = true

    @State private var sparkles: [Sparkle] = []
    @State private var rise = false        // checkmark lift + fade
    @State private var glow = false        // gold bloom
    @State private var chipIn = false

    private let gold = Color(red: 0.98, green: 0.78, blue: 0.30)

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height * 0.44
            ZStack {
                // Soft gold bloom behind the mark
                RadialGradient(colors: [gold.opacity(0.55), gold.opacity(0.0)],
                               center: .center, startRadius: 2, endRadius: 150)
                    .frame(width: 300, height: 300)
                    .scaleEffect(glow ? 1.0 : 0.3)
                    .opacity(glow ? 0 : 0.9)
                    .position(x: cx, y: cy)

                // Sparkles floating up and away
                ForEach(sparkles) { s in
                    Image(systemName: "sparkle")
                        .font(.system(size: s.size))
                        .foregroundStyle(gold)
                        .position(x: cx + s.dx, y: cy + (rise ? s.dy : 0))
                        .scaleEffect(rise ? s.endScale : 0.2)
                        .opacity(rise ? 0 : 1)
                        .animation(.easeOut(duration: s.duration).delay(s.delay), value: rise)
                }

                // Checkmark glows gold, lifts and dissolves
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 78, weight: .semibold))
                    .foregroundStyle(gold)
                    .shadow(color: gold.opacity(0.7), radius: glow ? 24 : 0)
                    .scaleEffect(rise ? 1.15 : 0.6)
                    .opacity(rise ? 0 : 1)
                    .offset(y: rise ? -70 : 0)
                    .position(x: cx, y: cy)

                // Gentle streak chip, rising softly
                streakChip
                    .position(x: cx, y: geo.size.height * 0.58)
                    .offset(y: chipIn ? 0 : 20)
                    .opacity(chipIn ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { run() }
    }

    private var streakChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(gold)
            Text(event.streak <= 1 ? "Done" : "\(event.streak) done today")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textMain)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(gold.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func run() {
        sparkles = (0..<12).map { _ in Sparkle() }

        if feedback {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            AudioServicesPlaySystemSound(1103)   // gentle "begin recording" chime — soft & short
        }

        withAnimation(.easeOut(duration: 0.7)) { glow = true }
        withAnimation(.easeOut(duration: 1.0).delay(0.05)) { rise = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) { chipIn = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.3)) { chipIn = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { onDone() }
    }
}

private struct Sparkle: Identifiable {
    let id = UUID()
    let dx: CGFloat          // horizontal offset from center
    let dy: CGFloat          // final vertical offset (negative = up)
    let size: CGFloat
    let endScale: CGFloat
    let delay: Double
    let duration: Double

    init() {
        dx = CGFloat.random(in: -90...90)
        dy = CGFloat.random(in: -150 ... -50)
        size = CGFloat.random(in: 12...22)
        endScale = CGFloat.random(in: 0.6...1.2)
        delay = Double.random(in: 0...0.2)
        duration = Double.random(in: 0.8...1.1)
    }
}
