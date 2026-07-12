// ScanReminderView.swift — Nudge (iOS / macCatalyst)
// "Scan reminders": pick or paste an image of a list → on-device OCR (ReminderScanner) →
// Claude structures the TEXT into items (AIScanParser) → an editable preview → save.
//
// PRIVACY: the image is read on-device by Vision; only the extracted text is sent to Claude.
// REVIEW: nothing is saved until the user taps Add. Items with no detected date are FLAGGED
// ("No date") but NOT blocked — the user can set a date or save them undated.

import SwiftUI
import PhotosUI
import UIKit

struct ScanReminderView: View {
    @EnvironmentObject var store: NudgeStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase { case pick, working, review }
    @State private var phase: Phase = .pick
    @State private var pickerItem: PhotosPickerItem?
    @State private var items: [ScannedItem] = []
    @State private var listId = "reminders"
    @State private var errorText: String?
    @State private var statusText = "Reading image…"

    private var aiKey: String { APIKeyStore.load() }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick:    pickPhase
                case .working: workingPhase
                case .review:  reviewPhase
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Scan Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(items.count)") { saveAll() }
                            .fontWeight(.bold)
                            .disabled(items.isEmpty)
                    }
                }
            }
            .onAppear { if let first = store.lists.first { listId = first.id } }
        }
    }

    // MARK: - Pick

    private var pickPhase: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(Theme.accent)
            VStack(spacing: 6) {
                Text("Scan a list into Nudge").font(.headline).foregroundStyle(Theme.textMain)
                Text("Pick a photo or paste a screenshot of a to-do list, note, or paper. Nudge reads it on your device and turns it into reminders you can review.")
                    .font(.subheadline).foregroundStyle(Theme.textMeta)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }

            if aiKey.isEmpty {
                Text("Add an Anthropic API key in Settings to use scanning.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.coral)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    label("photo.on.rectangle", "Choose Image")
                }
                .disabled(aiKey.isEmpty)

                Button { pasteImage() } label: { label("doc.on.clipboard", "Paste Image") }
                    .disabled(aiKey.isEmpty)
            }
            .padding(.horizontal, 30)

            if let e = errorText {
                Text(e).font(.caption).foregroundStyle(Theme.coral)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Spacer(); Spacer()
        }
        .padding()
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await run(on: img)
                } else {
                    errorText = "Couldn't load that image."
                }
            }
        }
    }

    private func label(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon); Text(text).fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func pasteImage() {
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image {
            Task { await run(on: img) }
        } else {
            errorText = "No image on the clipboard. Copy a screenshot first, then Paste."
        }
    }

    // MARK: - Working

    private var workingPhase: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large).tint(Theme.accent)
            Text(statusText).font(.subheadline).foregroundStyle(Theme.textMeta)
            Spacer()
        }
    }

    /// OCR on-device, then send only the text to Claude.
    private func run(on image: UIImage) async {
        errorText = nil
        phase = .working
        statusText = "Reading image on your device…"
        do {
            let text = try await ReminderScanner.extractText(from: image)
            statusText = "Understanding your list…"
            let parsed = try await AIScanParser.parse(text: text, apiKey: aiKey,
                                                       model: AIScheduler.defaultModel)
            guard !parsed.isEmpty else {
                errorText = "No reminders found. Try a clearer image."
                phase = .pick; return
            }
            items = parsed
            phase = .review
        } catch {
            errorText = error.localizedDescription
            phase = .pick
        }
    }

    // MARK: - Review

    private var reviewPhase: some View {
        List {
            Section {
                ForEach($items) { $item in ScanRow(item: $item) }
                    .onDelete { items.remove(atOffsets: $0) }
            } header: {
                Text("^[\(items.count) reminder](inflect: true) — edit, set dates, or swipe to remove")
                    .textCase(nil)
            } footer: {
                Text("Reminders with no date are marked. Set a date, or add them undated.")
            }

            Section {
                Picker("Add to list", selection: $listId) {
                    ForEach(store.lists) { l in Text(l.name).tag(l.id) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func saveAll() {
        for item in items {
            let hasDue = item.dateTime != nil
            store.saveReminder(
                editing: nil,
                title: item.title,
                notes: "",
                hasDue: hasDue,
                due: item.dateTime ?? Date(),
                hasTime: hasDue ? item.hasTime : false,
                listId: listId,
                priority: "normal"
            )
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// One editable row in the review list. Shows title, a "No date" flag when undated, and
/// controls to set a date + time or clear them again.
private struct ScanRow: View {
    @Binding var item: ScannedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $item.title, axis: .vertical)
                .font(.body.weight(.medium))

            if item.dateTime == nil {
                HStack(spacing: 8) {
                    Label("No date", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.coral)
                    Spacer()
                    Button("Set date") {
                        item.dateTime = defaultFutureTime()
                        item.hasTime = true
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    DatePicker(
                        "When",
                        selection: Binding(
                            get: { item.dateTime ?? defaultFutureTime() },
                            set: { item.dateTime = $0 }
                        ),
                        displayedComponents: item.hasTime ? [.date, .hourAndMinute] : [.date]
                    )
                    .font(.caption)

                    HStack {
                        Toggle("Include time", isOn: $item.hasTime)
                            .font(.caption)
                            .toggleStyle(.switch)
                        Spacer()
                        Button("Clear date") { item.dateTime = nil }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textMeta)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Tomorrow at 09:00 local — a neutral default when the user chooses to add a date.
    private func defaultFutureTime() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
