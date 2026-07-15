// BulkMoveView.swift — Nudge (iOS)
// Bulk-move sheet for multi-select on Today/Overdue. Every selected reminder gets its
// own target date (defaulted to a shared "move all to" date you pick first, but each
// row can be dragged to a different day independently — e.g. some tomorrow, some next
// week, in one action). Times either stay as each reminder's own time-of-day, or get
// overridden to a single shared time for everything being moved.

import SwiftUI

struct BulkMoveView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    let reminders: [Reminder]

    /// Per-reminder target date. Seeded from `sharedDate` on appear, then editable
    /// independently — this is what lets some reminders move to tomorrow and others
    /// to next week in the same action.
    @State private var targetDates: [String: Date] = [:]
    @State private var sharedDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var useOneTimeForAll = false
    @State private var sharedTime = Date()
    @State private var showConflictWarning = false

    private var sortedReminders: [Reminder] {
        reminders.sorted { (parseDate($0.dueDate) ?? .distantFuture) < (parseDate($1.dueDate) ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Moving \(reminders.count) reminder\(reminders.count == 1 ? "" : "s")")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)

                    // Move-all-to-this-day picker — applies to every row that hasn't been
                    // individually overridden below.
                    VStack(alignment: .leading, spacing: 12) {
                        Text("MOVE ALL TO").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.accent)
                        DatePicker("", selection: $sharedDate, displayedComponents: [.date])
                            .datePickerStyle(.graphical).tint(Theme.accent).labelsHidden()
                            .onChange(of: sharedDate) { _, newDate in
                                applySharedDateToAll(newDate)
                            }

                        Toggle(isOn: $useOneTimeForAll.animation(Theme.spring)) {
                            Text("Set one time for all").font(.subheadline.weight(.medium)).foregroundStyle(Theme.textMain)
                        }
                        .tint(Theme.accent)

                        if useOneTimeForAll {
                            DatePicker("", selection: $sharedTime, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                            Text("Every reminder below moves to this time.")
                                .font(.caption).foregroundStyle(Theme.textMeta)
                        } else {
                            Text("Each reminder keeps its own time — only the date changes.")
                                .font(.caption).foregroundStyle(Theme.textMeta)
                        }
                    }
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                    // Per-reminder overrides — each defaults to the shared date above, but can
                    // be pulled to a different day without affecting the others.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("REMINDERS").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Theme.textMeta)
                        ForEach(sortedReminders) { r in
                            reminderRow(r)
                        }
                    }

                    Button {
                        confirmAndApply()
                    } label: {
                        Text("Move \(reminders.count) Reminder\(reminders.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                }
                .padding(18)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Move Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                for r in reminders { targetDates[r.id] = sharedDate }
            }
            .alert("Some reminders clash with your calendar", isPresented: $showConflictWarning) {
                Button("Move anyway", role: .destructive) { applyAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("One or more of the new times overlaps an existing calendar event.")
            }
        }
        .tint(Theme.accent)
        .presentationBackground(Theme.bg)
    }

    private func reminderRow(_ r: Reminder) -> some View {
        let binding = Binding<Date>(
            get: { targetDates[r.id] ?? sharedDate },
            set: { targetDates[r.id] = $0; touchedIds.insert(r.id) }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(r)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                        .lineLimit(1)
                    if let lbl = dueLabel(r) {
                        Text("Currently \(lbl)").font(.caption).foregroundStyle(Theme.textMeta)
                    }
                }
                Spacer()
            }
            DatePicker("", selection: binding, displayedComponents: [.date])
                .datePickerStyle(.compact).labelsHidden()
                .tint(Theme.accent)
        }
        .padding(12)
        .background(Theme.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Re-seed every row the user hasn't individually overridden — a naive "set every
    /// row" would also stomp on a per-reminder date the user just deliberately picked.
    private func applySharedDateToAll(_ newDate: Date) {
        for r in reminders where !touchedIds.contains(r.id) {
            targetDates[r.id] = newDate
        }
    }

    /// Reminders whose date the user has explicitly changed away from the shared date —
    /// tracked so the shared-date picker doesn't clobber a deliberate per-row override.
    @State private var touchedIds: Set<String> = []

    /// Compute the final date+time for a reminder given the current toggle state.
    private func finalDate(for r: Reminder) -> Date {
        let day = targetDates[r.id] ?? sharedDate
        let cal = Calendar.current
        if useOneTimeForAll {
            let timeComps = cal.dateComponents([.hour, .minute], from: sharedTime)
            return cal.date(bySettingHour: timeComps.hour ?? 9, minute: timeComps.minute ?? 0, second: 0, of: day) ?? day
        } else {
            // Keep each reminder's own time-of-day; fall back to 9am for undated/no-time reminders.
            let original = parseDate(r.dueDate)
            let comps = original.map { cal.dateComponents([.hour, .minute], from: $0) }
            let hour = comps?.hour ?? 9
            let minute = comps?.minute ?? 0
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
    }

    private func confirmAndApply() {
        let hasConflict = reminders.contains { r in
            CalendarService.shared.conflictDescription(at: finalDate(for: r)) != nil
        }
        if hasConflict {
            showConflictWarning = true
        } else {
            applyAll()
        }
    }

    private func applyAll() {
        for r in reminders {
            store.reschedule(r.id, to: finalDate(for: r))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }
}
