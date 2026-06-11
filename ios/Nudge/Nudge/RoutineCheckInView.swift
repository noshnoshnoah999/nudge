// RoutineCheckInView.swift — Nudge (iOS)
// The morning "did you do it last night?" sheet for nightly routine reminders
// (KP / Epiduo). Shown once on the first app-open of a day when a routine lapsed.
//   Yes → rolls forward to the next occurrence.
//   Not yet → move to tonight / tomorrow / a chosen day.
// Also surfaces the adaptive "ready to step up?" prompt (e.g. Epiduo ramp-up).

import SwiftUI

struct RoutineCheckInView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss

    let lapsed: [Reminder]      // snapshot taken when the sheet was presented
    let stepUps: [Reminder]

    @State private var resolved: Set<String> = []
    @State private var expanded: String? = nil          // which card is in "pick a day" mode
    @State private var pickDate = Date()

    private var pending: [Reminder] { lapsed.filter { !resolved.contains($0.id) } }
    private var pendingStepUps: [Reminder] { stepUps.filter { !resolved.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Last night's routine")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textMain)
                    Text("You didn't tick these off — did you do them?")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)

                    ForEach(pending) { r in checkInCard(r) }
                    ForEach(pendingStepUps) { r in stepUpCard(r) }

                    if pending.isEmpty && pendingStepUps.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(Theme.sage)
                            Text("All sorted").font(.headline).foregroundStyle(Theme.textMain)
                        }.frame(maxWidth: .infinity).padding(.top, 30)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(pending.isEmpty && pendingStepUps.isEmpty ? "Done" : "Later") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: pending.count) { _, _ in autoDismiss() }
        .onChange(of: pendingStepUps.count) { _, _ in autoDismiss() }
    }

    private func autoDismiss() {
        if pending.isEmpty && pendingStepUps.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dismiss() }
        }
    }

    // MARK: - Cards

    private func checkInCard(_ r: Reminder) -> some View {
        let night = parseDate(r.dueDate) ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.headline).foregroundStyle(Theme.textMain)
                    Text("Was due \(night, format: .dateTime.weekday(.wide).day().month())")
                        .font(.caption).foregroundStyle(Theme.textMeta)
                }
                Spacer()
            }

            if expanded == r.id {
                Text("When will you do it?").font(.subheadline.weight(.medium)).foregroundStyle(Theme.textMeta)
                HStack(spacing: 8) {
                    pill("Tonight") { reschedule(r, store.dayFromNow(0)) }
                    pill("Tomorrow") { reschedule(r, store.dayFromNow(1)) }
                }
                DatePicker("Another day", selection: $pickDate, in: store.dayFromNow(0)..., displayedComponents: .date)
                    .tint(Theme.accent).font(.subheadline)
                Button { reschedule(r, pickDate) } label: {
                    Text("Move to this day").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                }
            } else {
                HStack(spacing: 10) {
                    Button { didIt(r, night: night) } label: {
                        Label("Yes, did it", systemImage: "checkmark")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Theme.sage, in: Capsule())
                    }.buttonStyle(PressableStyle())
                    Button { withAnimation(Theme.spring) { pickDate = store.dayFromNow(0); expanded = r.id } } label: {
                        Text("Not yet").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Theme.accent.opacity(0.14), in: Capsule())
                    }.buttonStyle(PressableStyle())
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func stepUpCard(_ r: Reminder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.circle.fill").foregroundStyle(Theme.accent)
                Text("\(r.title) — skin check").font(.headline).foregroundStyle(Theme.textMain)
                Spacer()
            }
            Text("Currently every \(store.routineIntervalDays(r)) day\(store.routineIntervalDays(r) == 1 ? "" : "s"). If your skin's reacting well, step it up?")
                .font(.subheadline).foregroundStyle(Theme.textMeta)
            HStack(spacing: 10) {
                Button { store.routineStepUp(r.id); resolved.insert(r.id) } label: {
                    Label("Step up", systemImage: "arrow.up").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11).background(Theme.accent, in: Capsule())
                }.buttonStyle(PressableStyle())
                Button { store.routineSnoozeAsk(r.id); resolved.insert(r.id) } label: {
                    Text("Not yet").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity).padding(.vertical, 11).background(Theme.accent.opacity(0.14), in: Capsule())
                }.buttonStyle(PressableStyle())
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private func pill(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Theme.accent.opacity(0.14), in: Capsule())
        }.buttonStyle(PressableStyle())
    }

    private func didIt(_ r: Reminder, night: Date) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.routineDidIt(r.id, night: night)
        withAnimation(Theme.spring) { _ = resolved.insert(r.id) }
    }
    private func reschedule(_ r: Reminder, _ day: Date) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.routineRescheduleTo(r.id, day: day)
        withAnimation(Theme.spring) { expanded = nil; _ = resolved.insert(r.id) }
    }
}
