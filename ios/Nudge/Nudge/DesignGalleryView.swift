// DesignGalleryView.swift — Nudge (iOS)
// TEMPORARY: three candidate visual styles on sample data so Noah can pick one.
// Remove once a direction is chosen and built for real.

import SwiftUI

struct GRow: Identifiable {
    let id = UUID()
    let title: String; let time: String; let list: String; let color: Color; let overdue: Bool
}

private let gOverdue = [
    GRow(title: "Pay rent", time: "9 May, 09:00", list: "Money", color: .orange, overdue: true),
    GRow(title: "Renew passport", time: "2 Jun", list: "UK Trip", color: .blue, overdue: true),
    GRow(title: "Book dentist", time: "5 May", list: "Personal", color: .purple, overdue: true)
]
private let gToday = [
    GRow(title: "Call mum", time: "14:00", list: "Personal", color: .purple, overdue: false),
    GRow(title: "Gym session", time: "18:00", list: "Health", color: .green, overdue: false)
]
private let gSoon = [
    GRow(title: "Submit history essay", time: "8 Jun", list: "Study", color: .indigo, overdue: false),
    GRow(title: "Pay Preply tutor", time: "10 Jun", list: "Money", color: .orange, overdue: false)
]

struct DesignGalleryView: View {
    @State private var style = 0
    private let names = ["1 · Minimal", "2 · StudyTrack", "3 · Bold"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Style", selection: $style) {
                ForEach(0..<names.count, id: \.self) { Text(names[$0]).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(12)
            Divider()
            Group {
                switch style {
                case 0: MinimalStyle()
                case 1: StudyTrackStyle()
                default: BoldStyle()
                }
            }
        }
        .navigationTitle("Preview designs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 1. Minimal & refined (Things-like: flat, airy, hairline dividers, no boxes)

private struct MinimalStyle: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good Afternoon").font(.largeTitle.weight(.bold))
                    Text("Saturday 6 June · 5 to do").font(.subheadline).foregroundStyle(.secondary)
                }
                sec("Overdue", gOverdue, accent: .red)
                sec("Today", gToday, accent: .secondary)
                sec("Upcoming", gSoon, accent: .secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .tint(.indigo)
    }
    private func sec(_ t: String, _ rows: [GRow], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(accent).padding(.bottom, 8)
            ForEach(rows) { r in
                HStack(spacing: 14) {
                    Image(systemName: "circle").font(.title3).foregroundStyle(.quaternary)
                    Text(r.title).font(.body)
                    Spacer()
                    Text(r.time).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 13)
                if r.id != rows.last?.id { Divider() }
            }
        }
    }
}

// MARK: - 2. StudyTrack-native (systemGroupedBackground + inset-grouped, like Apple's apps)

private struct StudyTrackStyle: View {
    var body: some View {
        List {
            Section("Overdue") { ForEach(gOverdue) { row($0) } }
            Section("Today") { ForEach(gToday) { row($0) } }
            Section("Upcoming") { ForEach(gSoon) { row($0) } }
        }
        .listStyle(.insetGrouped)
        .tint(.blue)
    }
    private func row(_ r: GRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "circle").foregroundStyle(r.overdue ? .red : .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.title)
                HStack(spacing: 6) {
                    Circle().fill(r.color).frame(width: 7, height: 7)
                    Text(r.list).font(.caption).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary)
                    Text(r.time).font(.caption).foregroundStyle(r.overdue ? .red : .secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 3. Bold & expressive (statement hero, chunky cards, strong type)

private struct BoldStyle: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GOOD AFTERNOON").font(.caption.weight(.heavy)).tracking(2).foregroundStyle(.white.opacity(0.85))
                    Text("3 overdue").font(.system(size: 42, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("Let's clear the backlog →").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: "6E5BF0"), Color(hex: "C24AC8")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                boldSec("OVERDUE", gOverdue)
                boldSec("TODAY", gToday)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }
    private func boldSec(_ t: String, _ rows: [GRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t).font(.title3.weight(.heavy))
            ForEach(rows) { r in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 3).fill(r.color).frame(width: 5, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.body.weight(.bold))
                        Text("\(r.list) · \(r.time)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "circle").font(.title2).foregroundStyle(.quaternary)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            }
        }
    }
}
