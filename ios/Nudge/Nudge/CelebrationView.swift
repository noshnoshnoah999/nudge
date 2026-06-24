// CelebrationView.swift — Nudge (iOS)
// The reward animation played when a reminder is completed: a confetti burst, a checkmark pop,
// and a "🔥 N done today" streak chip — plus a success haptic and a soft chime. ~1.3s, designed
// to feel like an achievement and nudge you to keep going.

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

    @State private var pieces: [ConfettiPiece] = []
    @State private var burst = false
    @State private var ringScale: CGFloat = 0.2
    @State private var ringOpacity: Double = 0.9
    @State private var chipIn = false

    private let palette: [Color] = [
        Theme.accent, .yellow, .pink, .green, .orange, .purple, .mint
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Confetti
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 1.6)
                        .rotationEffect(.degrees(burst ? p.spin : 0))
                        .position(x: p.x * geo.size.width,
                                  y: burst ? p.endY * geo.size.height : -40)
                        .opacity(burst ? 0 : 1)
                        .animation(.easeOut(duration: p.duration).delay(p.delay), value: burst)
                }

                // Center checkmark + expanding ring
                ZStack {
                    Circle()
                        .stroke(Theme.accent, lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 84, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .scaleEffect(burst ? 1 : 0.1)
                        .opacity(burst ? 1 : 0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: burst)
                }
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)

                // Streak chip
                streakChip
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.56)
                    .offset(y: chipIn ? 0 : 24)
                    .opacity(chipIn ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { run() }
    }

    private var streakChip: some View {
        HStack(spacing: 8) {
            Text("🔥").font(.title3)
            Text(event.streak <= 1 ? "Nice — that's done!"
                                   : "\(event.streak) done today")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(Theme.accent, in: Capsule())
        .shadow(color: Theme.accent.opacity(0.5), radius: 12, y: 4)
    }

    private func run() {
        pieces = (0..<26).map { _ in ConfettiPiece(palette: palette) }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1025)   // gentle "tweet" success chime

        withAnimation(.easeOut(duration: 0.5)) { ringScale = 1.6; ringOpacity = 0 }
        burst = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) { chipIn = true }

        // Fade the chip out then dismiss (~1.3s total).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.3)) { chipIn = false }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { onDone() }
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat            // 0...1 horizontal start (clustered around center)
    let endY: CGFloat         // 0...1 final vertical
    let size: CGFloat
    let color: Color
    let spin: Double
    let delay: Double
    let duration: Double

    init(palette: [Color]) {
        x = CGFloat.random(in: 0.2...0.8)
        endY = CGFloat.random(in: 0.7...1.05)
        size = CGFloat.random(in: 7...12)
        color = palette.randomElement() ?? .yellow
        spin = Double.random(in: -360...360)
        delay = Double.random(in: 0...0.12)
        duration = Double.random(in: 0.9...1.25)
    }
}
