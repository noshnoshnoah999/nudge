// QuickCatchView.swift — Nudge (iOS)
// The "catch a thought" fast-capture popup, run from the Control Center button.
// Flow: type a thought → Claude reads it and picks a smart date/time (avoiding busy
// calendar intervals and already-loaded days) → a confirmation screen where the user
// can adjust the time → save. If there's no API key or the call fails, a built-in
// heuristic (SmartScheduler) supplies the time instead, so capture never blocks.

import SwiftUI

struct QuickCatchView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("anthropic_api_key") private var aiKey = ""

    private enum Phase { case input, thinking, confirm }
    @State private var phase: Phase = .input
    @State private var thought = ""
    @FocusState private var focused: Bool

    // Suggestion being confirmed (editable).
    @State private var title = ""
    @State private var when = Date()
    @State private var hasTime = true
    @State private var priority = "normal"
    @State private var reason = ""
    @State private var usedAI = false
    @State private var errNote: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .input:    inputScreen
                case .thinking: thinkingScreen
                case .confirm:  confirmScreen
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .presentationDetents(phase == .input ? [.height(260)] : [.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: Step 1 — capture
    private var inputScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Catch a thought")
                    .font(.title2.bold()).foregroundStyle(Theme.textMain)
                Text("Just get it out of your head — Nudge will pick a smart time.")
                    .font(.subheadline).foregroundStyle(Theme.textMeta)
            }
            // NOTE: deliberately NOT axis:.vertical inside a scroll view — that won't
            // focus on iPhone (known Nudge gotcha). Single-line field, autofocused.
            TextField("e.g. book dentist, reply to Sam…", text: $thought)
                .focused($focused)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.go)
                .onSubmit(go)

            Button(action: go) {
                Text("Find a time")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(canGo ? Theme.accent : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(canGo ? .white : Theme.textMeta)
            }
            .disabled(!canGo)
            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true } }
    }

    private var canGo: Bool { !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Step 2 — Claude is choosing
    private var thinkingScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text("Finding a good time…")
                .font(.headline).foregroundStyle(Theme.textMain)
            Text("\u{201C}\(thought.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                .font(.subheadline).foregroundStyle(Theme.textMeta)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Step 3 — confirm / adjust
    private var confirmScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(usedAI ? "Suggested time" : "Picked a time")
                        .font(.caption.bold()).foregroundStyle(Theme.textMeta)
                    TextField("Reminder", text: $title)
                        .font(.title3.bold()).foregroundStyle(Theme.textMain)
                        .textFieldStyle(.plain)
                    if !reason.isEmpty {
                        Label(reason, systemImage: usedAI ? "sparkles" : "wand.and.stars")
                            .font(.footnote).foregroundStyle(Theme.accent)
                    }
                    if let errNote {
                        Text(errNote).font(.caption).foregroundStyle(Theme.textMeta)
                    }
                }

                VStack(spacing: 0) {
                    Toggle("Specific time", isOn: $hasTime)
                        .padding(.horizontal, 14).padding(.vertical, 10).tint(Theme.accent)
                    Divider().background(Theme.hairline)
                    DatePicker("When", selection: $when,
                               displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                        .padding(.horizontal, 14).padding(.vertical, 6)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))

                Picker("Priority", selection: $priority) {
                    Text("Low").tag("low"); Text("Normal").tag("normal"); Text("High").tag("high")
                }
                .pickerStyle(.segmented)

                Button(action: save) {
                    Text("Add to Nudge")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: Actions
    private func go() {
        guard canGo else { return }
        focused = false
        let captured = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(Theme.snappy) { phase = .thinking }

        Task {
            let busy = CalendarService.shared.busyIntervals()
            let now = Date()
            var suggestion: AIScheduler.CatchSuggestion?
            if !aiKey.isEmpty {
                suggestion = try? await AIScheduler.suggestSlot(
                    thought: captured, upcoming: store.reminders, busy: busy,
                    now: now, apiKey: aiKey, model: AIScheduler.defaultModel)
            }
            await MainActor.run {
                if let s = suggestion {
                    title = s.title; when = s.date; hasTime = s.hasTime
                    priority = s.priority; reason = s.reason; usedAI = true; errNote = nil
                } else {
                    // Fallback: tomorrow in the day's free window, nudged off busy intervals.
                    let cal = Calendar.current
                    let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
                    let wd = cal.component(.weekday, from: day)
                    var comps = cal.dateComponents([.year, .month, .day], from: day)
                    comps.hour = (wd == 1 || wd == 7) ? 11 : 18; comps.minute = 0
                    var slot = cal.date(from: comps) ?? day
                    var guardN = 0
                    while busy.contains(where: { $0.contains(slot) }) && guardN < 12 {
                        slot = Calendar.current.date(byAdding: .hour, value: 1, to: slot) ?? slot
                        guardN += 1
                    }
                    title = captured; when = slot; hasTime = true
                    priority = "normal"; reason = "Tomorrow — a quiet slot"
                    usedAI = false
                    errNote = aiKey.isEmpty ? "Add an API key in Settings for AI-picked times." : nil
                }
                withAnimation(Theme.snappy) { phase = .confirm }
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.saveReminder(editing: nil, title: t, notes: "",
                           hasDue: true, due: when, hasTime: hasTime,
                           listId: "reminders", priority: priority)
        dismiss()
    }
}
