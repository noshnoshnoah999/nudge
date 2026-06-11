// SectionStore.swift — Nudge
// Named sections per list (so an empty section can exist and be dragged into).
// Stored locally; section assignment itself lives on each reminder (`section`).

import Foundation

enum SectionStore {
    private static func key(_ listId: String) -> String { "sections." + listId }

    static func names(for listId: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(listId)) ?? []
    }
    static func add(_ name: String, to listId: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var n = names(for: listId)
        guard !t.isEmpty, !n.contains(t) else { return }
        n.append(t)
        UserDefaults.standard.set(n, forKey: key(listId))
    }
    static func remove(_ name: String, from listId: String) {
        var n = names(for: listId); n.removeAll { $0 == name }
        UserDefaults.standard.set(n, forKey: key(listId))
    }
}
