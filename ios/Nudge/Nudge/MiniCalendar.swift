// MiniCalendar.swift — Nudge (iOS)
// A themed month calendar for picking a date. Replaces the system graphical DatePicker so
// we control the styling — in particular making TODAY clearly visible (bold + accent ring),
// which the system picker renders as a faint tinted number.

import SwiftUI

struct MiniCalendar: View {
    @Binding var date: Date
    @State private var month: Date
    @State private var dragOffset: CGFloat = 0
    @State private var slideForward = true
    private let cal = Calendar.current

    init(date: Binding<Date>) {
        _date = date
        let start = Calendar.current.dateInterval(of: .month, for: date.wrappedValue)?.start ?? date.wrappedValue
        _month = State(initialValue: start)
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: month)
    }

    /// Cells for the month grid: leading blanks (Monday-first) then each day.
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.dateInterval(of: .month, for: month)?.start else { return [] }
        let weekday = cal.component(.weekday, from: first)   // 1 = Sun … 7 = Sat
        let leading = (weekday + 5) % 7                       // Monday-first offset
        var out = [Date?](repeating: nil, count: leading)
        for d in range { out.append(cal.date(byAdding: .day, value: d - 1, to: first)) }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(monthTitle).font(.headline.weight(.bold)).foregroundStyle(Theme.textMain)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left").font(.headline.weight(.bold)) }
                Button { step(1) } label: { Image(systemName: "chevron.right").font(.headline.weight(.bold)) }
            }
            .tint(Theme.accent)
            HStack(spacing: 0) {
                ForEach(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], id: \.self) { d in
                    Text(d).font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                        .frame(maxWidth: .infinity)
                }
            }
            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                        if let d { dayCell(d) } else { Color.clear.frame(height: 38) }
                    }
                }
                .id(month)
                .transition(.asymmetric(
                    insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                    removal:   .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .offset(x: dragOffset)
            .contentShape(Rectangle())
            .clipped()
            // Mac Catalyst: two-finger trackpad swipes arrive as scroll events, which
            // SwiftUI's DragGesture never sees — catch them here and flip the month.
            .overlay(TrackpadScrollCatcher { dx in step(dx < 0 ? 1 : -1) })
            // Horizontal swipe to change months (left = next, right = previous).
            // highPriorityGesture so a real drag wins over a day-cell tap.
            .highPriorityGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in
                        guard abs(v.translation.width) > abs(v.translation.height) else { return }
                        dragOffset = v.translation.width
                    }
                    .onEnded { v in
                        let w = v.translation.width
                        if abs(w) > 50 && abs(w) > abs(v.translation.height) {
                            step(w < 0 ? 1 : -1)
                        }
                        withAnimation(Theme.snappy) { dragOffset = 0 }
                    }
            )
        }
    }

    private func dayCell(_ d: Date) -> some View {
        let isSel = cal.isDate(d, inSameDayAs: date)
        let isToday = cal.isDateInToday(d)
        return Button {
            // Keep the time-of-day from the current selection; just change the day.
            let t = cal.dateComponents([.hour, .minute], from: date)
            var c = cal.dateComponents([.year, .month, .day], from: d)
            c.hour = t.hour; c.minute = t.minute
            withAnimation(Theme.snappy) { date = cal.date(from: c) ?? d }
        } label: {
            ZStack {
                if isSel { Circle().fill(Theme.accent).frame(width: 36, height: 36) }
                else if isToday { Circle().stroke(Theme.accent, lineWidth: 2).frame(width: 36, height: 36) }
                Text("\(cal.component(.day, from: d))")
                    .font(.callout.weight(isSel || isToday ? .bold : .regular))
                    .foregroundStyle(isSel ? .white : (isToday ? Theme.accent : Theme.textMain))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
    }

    private func step(_ n: Int) {
        guard let m = cal.date(byAdding: .month, value: n, to: month) else { return }
        slideForward = n > 0
        withAnimation(Theme.snappy) { month = cal.dateInterval(of: .month, for: m)?.start ?? m }
    }
}

/// A transparent overlay that catches horizontal trackpad/scroll swipes. On Mac Catalyst
/// two-finger swipes are delivered as continuous scroll events (not touches), so a normal
/// SwiftUI DragGesture can't see them. A UIPanGestureRecognizer with `allowedScrollTypesMask`
/// receives them. `onSwipe(dx)` fires once per gesture with the horizontal direction.
private struct TrackpadScrollCatcher: UIViewRepresentable {
    let onSwipe: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSwipe: onSwipe) }

    func makeUIView(context: Context) -> UIView {
        let v = PassthroughView()
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        pan.allowedScrollTypesMask = .continuous   // trackpad two-finger scroll
        pan.maximumNumberOfTouches = 0             // scroll only, never steal taps from day cells
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.onSwipe = onSwipe }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onSwipe: (CGFloat) -> Void
        private var fired = false
        init(onSwipe: @escaping (CGFloat) -> Void) { self.onSwipe = onSwipe }

        @objc func handle(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began, .possible: fired = false
            case .changed:
                guard !fired else { return }
                let t = g.translation(in: g.view)
                if abs(t.x) > 28 && abs(t.x) > abs(t.y) {
                    fired = true
                    onSwipe(t.x)
                }
            case .ended, .cancelled, .failed: fired = false
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    /// Captures only scroll events (so the trackpad pan recognizer fires); lets clicks and
    /// touches fall straight through to the SwiftUI day-cell buttons underneath.
    final class PassthroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if event?.type == .scroll { return self }
            return nil
        }
    }
}
