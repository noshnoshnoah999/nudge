// MiniCalendar.swift — Nudge (iOS)
// A themed month calendar for picking a date. Replaces the system graphical DatePicker so
// we control the styling — in particular making TODAY clearly visible (bold + accent ring),
// which the system picker renders as a faint tinted number.

import SwiftUI

struct MiniCalendar: View {
    @Binding var date: Date
    @State private var month: Date
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d { dayCell(d) } else { Color.clear.frame(height: 38) }
                }
            }
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
        withAnimation(Theme.snappy) { month = cal.dateInterval(of: .month, for: m)?.start ?? m }
    }
}
