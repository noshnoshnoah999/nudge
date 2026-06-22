// TimetableView.swift — Nudge
// A draggable day timetable. Pick a day, see its timed reminders on an hour grid,
// and drag a reminder up/down to change its time. Opened after Smart Reschedule
// (to fine-tune the spread) or on its own.

import SwiftUI

struct TimetableView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    var undoChanges: [RescheduleChange]? = nil

    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var editing: Reminder?
    @State private var dragY: [String: CGFloat] = [:]
    @State private var undone = false

    private let cal = Calendar.current
    private let hourH: CGFloat = 60
    private let labelW: CGFloat = 46

    // Grid bounds flex to include every reminder on the day (and "now" if today),
    // so early/late items aren't clamped onto the wrong line. Defaults to 7–23.
    private var startHour: Int { hourRange(for: selected).lo }
    private var endHour: Int { hourRange(for: selected).hi }
    private func hourRange(for day: Date) -> (lo: Int, hi: Int) {
        var lo = 7, hi = 23
        for r in timed(day) {
            if let d = parseDate(r.dueDate) {
                let h = cal.component(.hour, from: d)
                lo = min(lo, h); hi = max(hi, h + 1)
            }
        }
        if cal.isDateInToday(day) {
            let nh = cal.component(.hour, from: Date())
            lo = min(lo, nh); hi = max(hi, nh + 1)
        }
        return (max(0, lo), min(23, hi))
    }

    private var days: [Date] {
        (0..<8).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: Date())) }
    }
    private func timed(_ day: Date) -> [Reminder] {
        store.open().filter {
            guard ($0.hasTime ?? false), let d = parseDate($0.dueDate) else { return false }
            return cal.isDate(d, inSameDayAs: day)
        }
    }
    private func yFor(_ d: Date) -> CGFloat {
        let h = Double(cal.component(.hour, from: d)) + Double(cal.component(.minute, from: d)) / 60.0
        return CGFloat(min(max(h, Double(startHour)), Double(endHour)) - Double(startHour)) * hourH
    }
    private func timeFrom(y: CGFloat, on day: Date) -> Date {
        var h = Double(startHour) + Double(y / hourH)
        h = min(max(h, Double(startHour)), Double(endHour))
        let hour = Int(h)
        let minute = min(Int(((h - Double(hour)) * 60 / 15).rounded()) * 15, 45)
        var c = cal.dateComponents([.year, .month, .day], from: day)
        c.hour = hour; c.minute = minute
        return cal.date(from: c) ?? day
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayPills
                Text("Drag a reminder to change its time")
                    .font(.caption).foregroundStyle(Theme.textMeta).padding(.bottom, 6)
                ScrollView {
                    GeometryReader { geo in
                        let lay = columns(selected)
                        ZStack(alignment: .topLeading) {
                            gridLines
                            ForEach(timed(selected)) { block($0, width: geo.size.width, layout: lay) }
                            if cal.isDateInToday(selected) { nowMarker }
                        }
                    }
                    .frame(height: CGFloat(endHour - startHour) * hourH + 20)
                    .padding(16)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let ch = undoChanges, !undone {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Undo") { store.undoReschedule(ch); undone = true; dismiss() }
                    }
                }
            }
            .sheet(item: $editing) { r in AddReminderView(editing: r).environmentObject(store) }
            .onAppear {
                if let first = undoChanges?.map(\.newDate).min() { selected = cal.startOfDay(for: first) }
            }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }

    private var dayPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(days, id: \.self) { d in
                    let on = cal.isDate(d, inSameDayAs: selected)
                    let count = timed(d).count
                    Button { withAnimation(Theme.snappy) { selected = d } } label: {
                        VStack(spacing: 3) {
                            Text(dayName(d)).font(.caption2.weight(.bold))
                            Text("\(cal.component(.day, from: d))").font(.headline.weight(.bold))
                            Circle().fill(count > 0 ? (on ? Color.white : Theme.accent) : .clear).frame(width: 5, height: 5)
                        }
                        .frame(width: 50, height: 66)
                        .background(on ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(on ? .white : Theme.textMain)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    // Live "now" line so today's view shows where the current moment sits.
    private var nowMarker: some View {
        HStack(spacing: 0) {
            Text(timeStr(Date())).font(.caption2.weight(.bold)).foregroundStyle(Theme.coral)
                .frame(width: labelW, alignment: .trailing)
            Circle().fill(Theme.coral).frame(width: 7, height: 7).padding(.horizontal, 3)
            Rectangle().fill(Theme.coral).frame(height: 1.5)
        }
        .offset(y: yFor(Date()) - 5)
        .zIndex(2)
        .allowsHitTesting(false)
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { h in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(format: "%02d:00", h)).font(.caption2).foregroundStyle(Theme.textMeta)
                        .frame(width: labelW, alignment: .trailing)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                .frame(height: hourH, alignment: .top)
            }
        }
    }

    private let blockH: CGFloat = 50

    private func block(_ r: Reminder, width: CGFloat, layout: [String: (col: Int, cols: Int)]) -> some View {
        let due = parseDate(r.dueDate) ?? selected
        let dragging = dragY[r.id] != nil
        let y = yFor(due) + (dragY[r.id] ?? 0)
        // Side-by-side columns so reminders at the same time don't hide behind each other.
        let lead: CGFloat = labelW + 8
        let gap: CGFloat = 6
        let (col, cols) = layout[r.id] ?? (0, 1)
        let avail = max(60, width - lead - 4)
        let w = (avail - CGFloat(cols - 1) * gap) / CGFloat(max(cols, 1))
        let x = lead + CGFloat(col) * (w + gap)
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle(r)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain).lineLimit(1)
                Text(timeStr(dragging ? timeFrom(y: y, on: selected) : due))
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
            if cols == 1 { Image(systemName: "line.3.horizontal").font(.caption).foregroundStyle(Theme.textMeta) }
        }
        .padding(.horizontal, cols > 1 ? 8 : 10).padding(.vertical, 8)
        .frame(width: w, height: blockH, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(Theme.accent.opacity(dragging ? 0.9 : 0.25), lineWidth: dragging ? 2 : 1))
        .shadow(color: .black.opacity(dragging ? 0.16 : 0), radius: 7, y: 3)
        .offset(x: x, y: y)
        .zIndex(dragging ? 1 : 0)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in dragY[r.id] = v.translation.height }
                .onEnded { v in
                    let newT = timeFrom(y: yFor(due) + v.translation.height, on: selected)
                    dragY[r.id] = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(Theme.spring) { store.reschedule(r.id, to: newT) }
                }
        )
        .onTapGesture { editing = r }
    }

    /// Lay reminders that overlap in time into side-by-side columns (calendar-style), so
    /// none hide behind another. Returns each reminder's column index + the column count
    /// of its overlap cluster.
    private func columns(_ day: Date) -> [String: (col: Int, cols: Int)] {
        let items = timed(day).compactMap { r -> (id: String, y: CGFloat)? in
            guard let d = parseDate(r.dueDate) else { return nil }
            return (r.id, yFor(d))
        }.sorted { $0.y < $1.y }
        guard !items.isEmpty else { return [:] }
        var result: [String: (Int, Int)] = [:]
        var i = 0
        while i < items.count {
            // Grow a cluster of transitively-overlapping blocks.
            var j = i
            var clusterBottom = items[i].y + blockH
            while j + 1 < items.count && items[j + 1].y < clusterBottom {
                j += 1
                clusterBottom = max(clusterBottom, items[j].y + blockH)
            }
            // Greedy column assignment within the cluster.
            var colBottoms: [CGFloat] = []
            var assign: [String: Int] = [:]
            for it in items[i...j] {
                if let c = colBottoms.firstIndex(where: { it.y >= $0 }) {
                    assign[it.id] = c; colBottoms[c] = it.y + blockH
                } else {
                    assign[it.id] = colBottoms.count; colBottoms.append(it.y + blockH)
                }
            }
            let cols = colBottoms.count
            for it in items[i...j] { result[it.id] = (assign[it.id]!, cols) }
            i = j + 1
        }
        return result
    }

    private func dayName(_ d: Date) -> String {
        if cal.isDateInToday(d) { return "Today" }
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d)
    }
    private func timeStr(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}
