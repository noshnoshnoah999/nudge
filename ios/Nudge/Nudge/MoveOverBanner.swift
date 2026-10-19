// MoveOverBanner.swift — Nudge (iOS + Mac)
//
// "N reminders left from yesterday — Run AI move-over / Skip today". Shown only on the device
// that claimed today's offer (see NudgeStore.checkMoveOverOffer, 2026-10-18).
//
// Its own View struct rather than a function inside ContentView (2026-10-19): ContentView.body
// was so large that, in Debug builds, it overflowed the iPhone's main-thread stack on launch.
// A separate struct keeps this banner's view values out of body's stack frame.
//
// Plain surface styling on purpose: it asks a question, it isn't an alert.

import SwiftUI

struct MoveOverOfferBanner: View {
    @EnvironmentObject var store: NudgeStore
    let offer: NudgeStore.MoveOverOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(offer.count) reminder\(offer.count == 1 ? "" : "s") left from yesterday")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Theme.textMain)
                    Text("Let Claude move the important ones to today?")
                        .font(.caption).foregroundStyle(Theme.textMeta)
                }
                Spacer()
            }
            if let err = store.moveOverError {
                Text(err).font(.caption).foregroundStyle(Theme.coral)
            }
            HStack(spacing: 10) {
                Button {
                    Task { await store.runMoveOver() }
                } label: {
                    HStack(spacing: 6) {
                        if store.moveOverRunning { ProgressView().controlSize(.small) }
                        Text(store.moveOverRunning ? "Moving…" : "Run AI move-over")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(store.moveOverRunning)

                Button {
                    withAnimation(Theme.spring) { store.skipMoveOver() }
                } label: {
                    Text("Skip today").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(store.moveOverRunning)
            }
        }
        .padding(12)
        .background {
            if Theme.minimal {
                Rectangle().fill(Theme.surface)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            } else {
                RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous).fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius(12), style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1))
            }
        }
        .padding(.horizontal, Theme.minimal ? 0 : 18).padding(.top, 8).padding(.bottom, 4)
    }
}
