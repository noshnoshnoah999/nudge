// GroupLog.swift — Nudge (iOS)
// Records each overnight (23:50) auto-grouping run and drives the orange "grouped overnight"
// banner shown on first open the next morning. Local-only (UserDefaults), last ~31 days —
// mirrors CarryOverLog so the two end-of-day AI features behave identically.

import Foundation
import SwiftUI
import Combine

/// One group that was applied in a run, with the member titles for the review sheet.
struct GroupedSet: Codable, Identifiable, Hashable {
    var id: String            // the groupId
    var title: String
    var reminderIds: [String]
    var reminderTitles: [String]
}

/// One night's grouping run.
struct GroupRunEntry: Codable, Identifiable, Hashable {
    var id: String            // processed day key, yyyy-MM-dd
    var ranAt: String         // ISO timestamp
    var groups: [GroupedSet]
    var groupedCount: Int { groups.reduce(0) { $0 + $1.reminderIds.count } }
}

final class GroupLog: ObservableObject {
    static let shared = GroupLog()

    @Published private(set) var entries: [GroupRunEntry] = []   // newest first
    /// Day key of a run the user hasn't reviewed yet → show the orange banner. nil = no banner.
    @Published var unseenDay: String?

    private let entriesKey = "groupRunEntries"
    private let unseenKey  = "groupRunUnseenDay"
    private let lastRunKey = "groupRunLastDay"

    private init() {
        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([GroupRunEntry].self, from: data) {
            entries = decoded
        }
        unseenDay = UserDefaults.standard.string(forKey: unseenKey)
        prune()
    }

    var lastProcessedDay: String? { UserDefaults.standard.string(forKey: lastRunKey) }

    func entry(for day: String) -> GroupRunEntry? { entries.first { $0.id == day } }
    var unseenEntry: GroupRunEntry? { unseenDay.flatMap(entry(for:)) }

    /// Record a completed run and raise the banner only if something was actually grouped.
    func record(_ entry: GroupRunEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        UserDefaults.standard.set(entry.id, forKey: lastRunKey)
        if !entry.groups.isEmpty {
            unseenDay = entry.id
            UserDefaults.standard.set(entry.id, forKey: unseenKey)
        }
        save()
    }

    /// Mark a day processed even when nothing was grouped, so we don't re-run the AI round-trip
    /// repeatedly within the same window.
    func markProcessed(_ day: String) {
        UserDefaults.standard.set(day, forKey: lastRunKey)
    }

    func dismissBanner() {
        unseenDay = nil
        UserDefaults.standard.removeObject(forKey: unseenKey)
    }

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: Date()) ?? Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        entries.removeAll { e in (f.date(from: e.id).map { $0 < cutoff }) ?? false }
    }

    private func save() {
        prune()
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: entriesKey)
        }
    }
}
