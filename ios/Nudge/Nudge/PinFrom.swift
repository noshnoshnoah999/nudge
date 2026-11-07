// PinFrom.swift — Nudge (iOS + Mac)
// "Pin from a date" (2026-11-07, Noah's spec). A pinned reminder can wait until a chosen day
// before joining Home's PINNED section. Rules agreed with Noah:
//   • Only available when the due date is tomorrow or later; the pin day is tomorrow-or-later
//     and never after the due day. Date only, no time.
//   • Cards show a small "Pins 1 Dec" label until the day arrives (Reminder.pendingPinDay).
//   • Moving a reminder with a pending pin day to ANOTHER day asks: Keep [date] (hidden if it
//     would be after the new due day) / Shift by the same amount / Pick a new date.
//     Edit screen + Reschedule ask per reminder; Bulk Move asks once for the whole batch.
//     Snooze and the automatic move-over don't ask (the pin day stays).
//   • Moved to today (or earlier): no question — a warning that the pin date won't happen and
//     it goes straight to Pinned after tapping Done; the pin day is then cleared.
//   • Repeating reminders: "This reminder only" (next occurrence pinned straight away) or
//     "All future ones too" (same gap before each due date — Reminder.pinFromGapDays).
// Data: Reminder.pinFrom / pinFromGapDays (optional, inside the reminder's JSON — no schema
// change). Store side: NudgeStore.normalizedPinFrom / applyPinMove / reschedule(_:to:pin:).

import SwiftUI

/// What to do with a pending pin-from day when a reminder moves to another day.
enum PinMove {
    case keep, shift, clear
    case set(Date)
    var isSet: Bool { if case .set = self { return true }; return false }
}

/// What moving a reminder to `newDue` means for its pin-from day.
enum PinMoveKind: Equatable {
    case none                 // no pending pin day, or the due DAY didn't change
    case warnToday            // moved to today/earlier (or date removed) — warn, then clear
    case ask(canKeep: Bool)   // moved to another future day — Keep / Shift / Pick
}

extension Reminder {
    func pinMoveKind(to newDue: Date?, now: Date = Date()) -> PinMoveKind {
        guard pendingPinDay != nil, let pf = parseDate(pinFrom) else { return .none }
        let cal = Calendar.current
        let oldDay = parseDate(dueDate).map { cal.startOfDay(for: $0) }
        let newDay = newDue.map { cal.startOfDay(for: $0) }
        if oldDay == newDay { return .none }
        guard let nd = newDay, nd > cal.startOfDay(for: now) else { return .warnToday }
        return .ask(canKeep: cal.startOfDay(for: pf) <= nd)
    }

    /// The pin day after "Shift by the same amount", or nil if that would be today/earlier
    /// (which means pinned straight away).
    func shiftedPinDay(to newDue: Date, now: Date = Date()) -> Date? {
        guard let pf = parseDate(pinFrom), let od = parseDate(dueDate) else { return nil }
        let cal = Calendar.current
        let delta = cal.dateComponents([.day], from: cal.startOfDay(for: od), to: cal.startOfDay(for: newDue)).day ?? 0
        guard let d = cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: pf)) else { return nil }
        return d > cal.startOfDay(for: now) ? d : nil
    }
}

func pinDayLabel(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d)
}

/// A pending move waiting on the user's pin-from answer. `items` = every reminder in the
/// move whose pin day is affected, with its new due date. `perform` does the move with the
/// chosen PinMove; cancelling does nothing (the move doesn't happen).
struct PendingPinMove: Identifiable {
    let id = UUID()
    let items: [(reminder: Reminder, newDue: Date)]
    let perform: (PinMove) -> Void

    private var cal: Calendar { Calendar.current }
    var askItems: [(reminder: Reminder, newDue: Date)] {
        items.filter { if case .ask = $0.reminder.pinMoveKind(to: $0.newDue) { return true }; return false }
    }
    var todayCount: Int { items.filter { $0.reminder.pinMoveKind(to: $0.newDue) == .warnToday }.count }
    var onlyWarnings: Bool { askItems.isEmpty }
    var canKeep: Bool {
        askItems.allSatisfy { $0.reminder.pinMoveKind(to: $0.newDue) == .ask(canKeep: true) }
    }
    /// Latest pin day allowed for "Pick a new date" — the earliest new due day in the batch.
    var pickMax: Date {
        askItems.map { cal.startOfDay(for: $0.newDue) }.min() ?? cal.startOfDay(for: Date())
    }
    var pickMin: Date { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date() }
}

/// Builds a PendingPinMove for a set of moves, or nil when no pin day is affected (the
/// caller then just moves straight away).
func pinMoveNeeded(_ moves: [(Reminder, Date)], perform: @escaping (PinMove) -> Void) -> PendingPinMove? {
    let hit = moves.filter { $0.0.pinMoveKind(to: $0.1) != .none }.map { (reminder: $0.0, newDue: $0.1) }
    return hit.isEmpty ? nil : PendingPinMove(items: hit, perform: perform)
}

/// The question shown when a move touches a pending pin-from day. Attach once per screen
/// with `.modifier(PinMovePrompt(pending: $pendingPinMove))`.
struct PinMovePrompt: ViewModifier {
    @Binding var pending: PendingPinMove?
    @State private var picking: PendingPinMove?
    @State private var pickDate = Date()

    private static let warning = "The \"Pin from\" date won't happen anymore — this reminder will go straight to Pinned after you tap Done."

    func body(content: Content) -> some View {
        content
            .alert("Moved to today", isPresented: Binding(
                get: { pending?.onlyWarnings == true },
                set: { if !$0 { pending = nil } })) {
                // Captured when the alert is built: SwiftUI may clear `pending` (via the binding)
                // before the button's action runs.
                if let p = pending {
                    Button("Done") { pending = nil; p.perform(.clear) }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text((pending?.items.count ?? 1) > 1
                     ? "\(pending?.todayCount ?? 0) of these have a \"Pin from\" date that won't happen anymore — they'll go straight to Pinned after you tap Done."
                     : Self.warning)
            }
            .confirmationDialog(title, isPresented: Binding(
                get: { pending != nil && pending?.onlyWarnings == false },
                set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let p = pending {
                    if p.canKeep, let keepLabel = keepLabel(p) {
                        Button(keepLabel) { pending = nil; p.perform(.keep) }
                    }
                    Button(shiftLabel(p)) { pending = nil; p.perform(.shift) }
                    Button("Pick a new date") {
                        pickDate = min(max(p.pickMin, parseDate(p.askItems.first?.reminder.pinFrom) ?? p.pickMin), p.pickMax)
                        pending = nil
                        picking = p
                    }
                    Button("Cancel", role: .cancel) { pending = nil }
                }
            } message: {
                Text(message)
            }
            .sheet(item: $picking) { p in
                PinFromPickerSheet(date: $pickDate, range: p.pickMin...p.pickMax,
                                   note: p.askItems.count > 1 ? "Used for all \(p.askItems.count) reminders." : nil,
                                   onDone: { picking = nil; p.perform(.set(pickDate)) },
                                   onCancel: { picking = nil })
            }
    }

    private var title: String {
        guard let p = pending else { return "" }
        if p.askItems.count == 1, let pf = parseDate(p.askItems[0].reminder.pinFrom) {
            return "This reminder pins to Home from \(pinDayLabel(pf))"
        }
        return "\(p.askItems.count) of these have a \"Pin from\" date"
    }

    private var message: String {
        guard let p = pending else { return "" }
        var m: String
        if p.askItems.count == 1 {
            m = "You're moving it to \(pinDayLabel(p.askItems[0].newDue)). What should the pin date do?"
        } else {
            m = "What should their pin dates do?"
        }
        if !p.canKeep { m += " Keeping it isn't possible — it would be after the new due date." }
        if p.todayCount > 0 { m += " \(p.todayCount) moving to today will go straight to Pinned." }
        return m
    }

    private func keepLabel(_ p: PendingPinMove) -> String? {
        if p.askItems.count == 1, let pf = parseDate(p.askItems[0].reminder.pinFrom) { return "Keep \(pinDayLabel(pf))" }
        return "Keep their pin dates"
    }

    private func shiftLabel(_ p: PendingPinMove) -> String {
        guard p.askItems.count == 1 else { return "Shift by the same amount" }
        let it = p.askItems[0]
        if let d = it.reminder.shiftedPinDay(to: it.newDue) { return "Shift to \(pinDayLabel(d))" }
        return "Shift (pins straight away)"
    }
}

/// Small date-only picker sheet for "Pick a new date".
struct PinFromPickerSheet: View {
    @Binding var date: Date
    let range: ClosedRange<Date>
    var note: String? = nil
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("", selection: $date, in: range, displayedComponents: [.date])
                    .datePickerStyle(.graphical).labelsHidden().tint(Theme.controlTint)
                Text("Pins to Home from the start of this day. Can't be after the due date.")
                    .font(.caption).foregroundStyle(Theme.textMeta)
                if let n = note { Text(n).font(.caption).foregroundStyle(Theme.textMeta) }
                Spacer()
            }
            .padding(18)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Pin from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone() }.fontWeight(.bold) }
            }
        }
        .tint(Theme.controlTint)
        .presentationDetents([.medium, .large])
    }
}
