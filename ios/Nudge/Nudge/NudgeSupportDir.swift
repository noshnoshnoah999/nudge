// NudgeSupportDir.swift — Nudge (iOS)
// Runtime files (cache, rotating backups, reschedule log, Apple-sync links, reminder
// images) live in ~/Library/Application Support/Nudge/ rather than ~/Documents/. On
// iOS this keeps them out of any Files-app exposure; on Mac Catalyst it keeps the
// visible Documents folder clean.
//
// RECOVERY NOTE: this helper was lost when an in-progress (uncommitted) refactor's
// NudgeStore.swift was deleted from the working tree; it's been re-created here from the
// call sites that expect it (ImageStore, RemindersSync, SmartScheduler, NudgeStore). The
// one-time migration moves anything left in the old Documents location across.

import Foundation

/// The app's private support directory (`…/Application Support/Nudge/`), created on first
/// use. Legacy files in Documents are migrated over once.
func nudgeSupportDirectory() -> URL {
    let fm = FileManager.default
    let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: true))
        ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("Nudge", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        migrateLegacyDocuments(into: dir, fm: fm)
    }
    return dir
}

/// Move runtime files that earlier builds wrote into ~/Documents into the support dir,
/// once, on the first run after the move. Best-effort: a failure leaves the old copy put.
private func migrateLegacyDocuments(into dir: URL, fm: FileManager) {
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let items = ["nudge_cache.json", "backups", "reschedule_log.json",
                 "nudge_sync_links.json", "nudge_images"]
    for name in items {
        let from = docs.appendingPathComponent(name)
        let to = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { continue }
        try? fm.moveItem(at: from, to: to)
    }
}
