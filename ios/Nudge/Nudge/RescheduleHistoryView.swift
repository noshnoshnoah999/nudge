// RescheduleHistoryView.swift — Nudge (iOS)
// Settings → Overdue → Reschedule history. Every Smart Reschedule run ever made,
// newest first, expandable to each reminder's old → new date, with per-run Undo.

import SwiftUI

struct RescheduleHistoryView: View {
    @EnvironmentObject var store: NudgeStore
    @State private var entries: [RescheduleLogEntry] = []
    @State private var expanded: Set<String> = []
    @State private var undone: Set<String> = []

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("No reschedules yet").font(.headline).foregroundStyle(Theme.textMain)
                    Text("When Smart Reschedule moves your overdue reminders, every run shows up here.")
                        .font(.subheadline).foregroundStyle(Theme.textMeta)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.top, 70).padding(.horizontal, 30)
            } else {
                VStack(spacing: 14) {
                    ForEach(entries) { entryCard($0) }
                }
                .padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Reschedule history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { RescheduleLog.clear(); entries = [] }
                }
            }
        }
        .onAppear { entries = RescheduleLog.all() }
    }

    private func entryCard(_ e: RescheduleLogEntry) -> some View {
        let isOpen = expanded.contains(e.id)
        let isUndone = undone.contains(e.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Theme.spring) {
                    if isOpen { expanded.remove(e.id) } else { expanded.insert(e.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: e.auto ? "wand.and.stars" : "hand.tap")
                        .font(.subheadline).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(e.auto ? "Automatic" : "Manual") · \(e.changes.count) moved")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textMain)
                        Text(stamp(e.date)).font(.caption).foregroundStyle(Theme.textMeta)
                    }
                    Spacer()
                    if isUndone {
                        Text("UNDONE").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMeta)
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textMeta).rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(e.changes) { c in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title).font(.subheadline).foregroundStyle(Theme.textMain).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(fmtOld(c.oldDue)).font(.caption).foregroundStyle(Theme.textMeta)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.textMeta)
                            Text(fmt(c.newDate)).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if !isUndone {
                    Button {
                        store.undoReschedule(e.changes)
                        withAnimation(Theme.spring) { _ = undone.insert(e.id) }
                    } label: {
                        Label("Undo this run", systemImage: "arrow.uturn.backward")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.coral)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        .opacity(isUndone ? 0.6 : 1)
    }

    private func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy, HH:mm"; return f.string(from: d)
    }
    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM, HH:mm"; return f.string(from: d)
    }
    private func fmtOld(_ iso: String?) -> String {
        guard let s = iso, let d = parseDate(s) else { return "No date" }
        let f = DateFormatter(); f.dateFormat = "d MMM, HH:mm"; return f.string(from: d)
    }
}
