// ImageStore.swift — Nudge (iOS)
// Local, on-device image attachments. Images live under
// Documents/nudge_images/<reminderId>/ — NOT in the synced cloud blob, so they
// stay on this phone (per Noah's choice). Keyed by reminder id; no model fields.

import UIKit

enum ImageStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nudge_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func dir(for id: String) -> URL {
        let d = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Persist a JPEG, returns its file URL.
    @discardableResult
    static func save(_ data: Data, for id: String) -> URL? {
        // Re-encode to JPEG to keep files small.
        let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
        let url = dir(for: id).appendingPathComponent(UUID().uuidString + ".jpg")
        do { try jpeg.write(to: url); return url } catch { return nil }
    }

    static func urls(for id: String) -> [URL] {
        let d = root.appendingPathComponent(id, isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return items.filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path }
    }

    static func hasImages(for id: String) -> Bool {
        let d = root.appendingPathComponent(id, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: d.path))?.isEmpty == false)
    }

    static func count(for id: String) -> Int { urls(for: id).count }

    static func delete(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    static func deleteAll(for id: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
    }

    static func image(_ url: URL) -> UIImage? { UIImage(contentsOfFile: url.path) }
}
