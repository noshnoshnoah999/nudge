// CloudSync.swift — Nudge
//
// Per-item cloud sync. Replaces the old "one JSON blob in one row, last writer wins"
// model, under which a delete had no representation at all: any device still holding a
// deleted reminder would silently re-upload it on its next push.
//
// The model here is one row per reminder / list / smart list, each carrying a row
// timestamp and a soft-delete (`deletedAt`) tombstone. Merging is per item, so two
// devices editing different reminders can no longer clobber one another, and a delete
// is a fact that propagates rather than an absence that gets undone.
//
// TWO CLOCKS, DELIBERATELY SEPARATE
//   • `SyncItem.updatedAt` (inside `data`) — the item's last *meaningful* edit. Read by
//     RemindersSync to arbitrate against Apple's `lastModifiedDate`. Sync never writes it.
//   • `SyncMeta.stamp` (the row's `updated_at` column) — the last time the item's *bytes*
//     changed, from any cause. This alone orders the merge.
//   They differ: `backfillFromApple()` rewrites a reminder's recurrence/url without
//   bumping `updatedAt` (on purpose, so the Apple tiebreak isn't skewed). Ordering sync on
//   `updatedAt` would strand those edits forever; ordering on the row stamp propagates them.
//
// STAMPS ARE STRINGS, COMPARED LEXICOGRAPHICALLY
//   Every stamp is written by `syncStamp()` in one fixed-width UTC form
//   ("2026-07-10T13:00:00.123Z"), so string order == chronological order. The `updated_at`
//   column is `text` for the same reason: PostgREST's `gt.` filter and this file's merge
//   then agree exactly, with no date parsing on either side. (Supabase returns timestamptz
//   with 6 fractional digits, which ISO8601DateFormatter refuses to parse.)

import Foundation
import CryptoKit

// MARK: - Canonical stamp

private let stampFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()

/// The one and only way a row timestamp is produced. Fixed width, UTC, always fractional.
func syncStamp(_ d: Date = Date()) -> String { stampFormatter.string(from: d) }

/// Parse a canonical stamp. Also tolerates the non-fractional ISO form found in older
/// `updatedAt` values written before this file existed.
func parseStamp(_ s: String?) -> Date? {
    guard let s, !s.isEmpty else { return nil }
    return stampFormatter.date(from: s) ?? parseDate(s)
}

/// The oldest representable stamp — "we have no idea when this changed", so the first real
/// edit from any device outranks it.
let epochStamp = "1970-01-01T00:00:00.000Z"

/// Normalise any ISO string (or nil) into a canonical, comparable stamp.
func normalizeStamp(_ s: String?) -> String {
    guard let d = parseStamp(s) else { return epochStamp }
    return syncStamp(d)
}

/// A stamp strictly greater than `other`, and no earlier than `d`. Used whenever an item's
/// stamp must advance: the revived item must outrank its own tombstone, otherwise the tie
/// rule in `mergeRows` hands the win to the delete and the undo silently reverts on the
/// other device's next pull.
///
/// `other` may be *ahead* of our clock (it can come from another device), so simply
/// nudging the local time forward is not enough — we have to step past `other` itself.
func syncStamp(after other: String, at d: Date = Date()) -> String {
    let bump = (parseStamp(other) ?? d).addingTimeInterval(0.001)
    return syncStamp(max(d, bump))
}

// MARK: - Rows

/// One row of a synced table. `data` is null for a tombstone.
struct CloudRow<T: SyncItem>: Codable {
    var id: String
    var data: T?
    var updated_at: String
    var deleted_at: String?

    // `user_id` is never sent: the column defaults to auth.uid(), and RLS pins it.

    /// Nils MUST serialise as explicit JSON nulls. The synthesized encoder omits them, and
    /// an omitted key in a merge-duplicates upsert leaves the existing column untouched —
    /// so reviving a deleted reminder would upload `data` but leave `deleted_at` set, and
    /// every other device would go on seeing a tombstone. That is precisely the bug this
    /// file exists to prevent, reintroduced one layer down.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(updated_at, forKey: .updated_at)
        if let data { try c.encode(data, forKey: .data) } else { try c.encodeNil(forKey: .data) }
        if let deleted_at { try c.encode(deleted_at, forKey: .deleted_at) } else { try c.encodeNil(forKey: .deleted_at) }
    }
}

/// Per-table sync bookkeeping, persisted alongside the items in the local cache.
///
/// `signature` is what makes dirtiness self-correcting: it is derived from the item's
/// actual bytes, so no mutation site has to remember to mark anything dirty. (There are
/// 108 mutation sites in NudgeStore alone; a hand-maintained dirty set would leak.)
struct SyncMeta: Codable {
    /// id → the row `updated_at` we believe the cloud has, or that we will push.
    var stamp: [String: String] = [:]
    /// id → `deletedAt`. A tombstone. Its id is absent from the live item array.
    var tombstone: [String: String] = [:]
    /// id → signature at the last *successful* push. Absent ⇒ never pushed ⇒ dirty.
    var pushedSig: [String: String] = [:]
    /// id → signature as of the last `refreshSignatures()`. Detects byte changes.
    var sig: [String: String] = [:]

    /// High-water mark of `updated_at` across every row we have pulled.
    var cursor: String? = nil

    /// IN MEMORY ONLY — never written to the cache (see CodingKeys).
    /// id → the item's `hashValue` and the signature computed from it last time.
    ///
    /// `refreshSignatures` runs on every persist and every push, and it used to JSON-encode
    /// and SHA-256 EVERY reminder each time, on the main thread. Ticking a reminder therefore
    /// cost a full re-hash of the whole list (twice — once at the tap, once at the push), which
    /// landed in the middle of the completion animation as a visible stutter (2026-10-18).
    /// An unchanged item has an unchanged `hashValue`, so its signature can be reused; only
    /// items whose content actually changed are re-encoded. Hasher is seeded per process,
    /// which is exactly why this must never be persisted.
    var memo: [String: SigMemo] = [:]

    private enum CodingKeys: String, CodingKey { case stamp, tombstone, pushedSig, sig, cursor }
}

/// One memoised signature: the content hash it was computed for, and the signature itself.
struct SigMemo {
    let hash: Int
    let sig: String
}

/// Signature of a live item: a hash of the exact bytes we would upload.
private func liveSignature<T: SyncItem>(_ item: T) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]   // stable across runs
    guard let d = try? enc.encode(item) else { return "L:?" }
    return "L:" + SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
}
private func tombSignature(_ deletedAt: String) -> String { "D:" + deletedAt }

extension SyncMeta {
    /// The current signature for `id`, tombstone or live. Nil if we know nothing about it.
    func signature<T: SyncItem>(of id: String, in items: [String: T]) -> String? {
        if let d = tombstone[id] { return tombSignature(d) }
        if let i = items[id] { return liveSignature(i) }
        return nil
    }
}

// MARK: - Local change detection

/// Recompute signatures and advance the row stamp of anything whose bytes changed since
/// the last call. Call once per persist, before pushing.
///
/// Everything downstream keys off this: an item is dirty iff `sig != pushedSig`, and its
/// row stamp is the moment its bytes last moved.
func refreshSignatures<T: SyncItem>(_ items: [T], meta: inout SyncMeta, now: Date = Date()) {
    var live: [String: T] = [:]
    for i in items { live[i.id] = i }

    var fresh: [String: String] = [:]
    for (id, item) in live {
        // Reuse the last signature when the content hash hasn't moved; see SyncMeta.memo.
        let h = item.hashValue
        if let m = meta.memo[id], m.hash == h {
            fresh[id] = m.sig
        } else {
            let s = liveSignature(item)
            fresh[id] = s
            meta.memo[id] = SigMemo(hash: h, sig: s)
        }
    }
    meta.memo = meta.memo.filter { live[$0.key] != nil }
    for (id, deletedAt) in meta.tombstone { fresh[id] = tombSignature(deletedAt) }

    for (id, s) in fresh where meta.sig[id] != s {
        // Bytes moved. A tombstone's stamp is its own deletedAt (so the delete's stamp is
        // the instant of deletion, not of the next persist); a live item's is now.
        let want = meta.tombstone[id] ?? syncStamp(now)
        // Stamps are monotonic per id, always. Without this an un-delete performed inside
        // the same millisecond as its tombstone would tie — and `mergeRows` gives ties to
        // the delete, so the revived reminder would vanish again on the next pull.
        if let old = meta.stamp[id], want <= old {
            meta.stamp[id] = syncStamp(after: old, at: now)
        } else {
            meta.stamp[id] = want
        }
    }
    meta.sig = fresh

    // Anything we no longer hold, live or tombstoned, is gone from our world entirely
    // (e.g. purged tombstone). Stop tracking it rather than resurrecting a stale stamp.
    meta.stamp = meta.stamp.filter { fresh[$0.key] != nil }
    meta.pushedSig = meta.pushedSig.filter { fresh[$0.key] != nil }
}

/// Bookkeeping for items adopted from the old single-blob cache on first launch of the
/// per-item build.
///
/// Everything is seeded as **already pushed**, with each stamp taken from the item's own
/// `updatedAt` — exactly what the server-side backfill derives its `updated_at` from. That
/// makes local and cloud agree by construction, so nothing is dirty and the first launch
/// pushes nothing.
///
/// Seeding them as *dirty* instead would be actively dangerous: every item would take a
/// fresh `now()` stamp, outranking the real cloud rows, and a device whose cache was stale
/// (say the Mac, offline while the iPhone was edited) would upload its entire stale copy
/// over the top of the newer one. The old whole-blob clobber, on its way out the door.
func seedMigratedMeta<T: SyncItem>(_ items: [T]) -> SyncMeta {
    var meta = SyncMeta()
    for item in items {
        let s = liveSignature(item)
        meta.sig[item.id] = s
        meta.pushedSig[item.id] = s
        meta.stamp[item.id] = normalizeStamp(item.updatedAt)
    }
    return meta
}

/// Ids whose bytes differ from what we last pushed.
func dirtyIds(_ meta: SyncMeta) -> [String] {
    meta.sig.compactMap { (id, s) in meta.pushedSig[id] == s ? nil : id }
}

/// The signatures of exactly what is about to be uploaded. Capture this BEFORE the network
/// call and hand it to `markPushed(_:meta:)` afterwards.
func signaturesBeingPushed(_ ids: [String], meta: SyncMeta) -> [String: String] {
    var out: [String: String] = [:]
    for id in ids { if let s = meta.sig[id] { out[id] = s } }
    return out
}

/// Record a successful upload of the bytes whose signatures were captured before it.
///
/// It used to record `meta.sig[id]` as it stood AFTER the upload returned. The push awaits the
/// network on the main actor, and anything can persist during that await — an edit, a
/// completion. That later change advanced `meta.sig`, so it was marked as pushed although only
/// the OLDER bytes ever left the device. The other device never received it, and its next
/// edit of that reminder overwrote this one: "I fixed it and it came back" (2026-10-18).
func markPushed(_ sent: [String: String], meta: inout SyncMeta) {
    for (id, s) in sent { meta.pushedSig[id] = s }
}

/// The rows to upload for `ids`.
func dirtyRows<T: SyncItem>(_ ids: [String], items: [T], meta: SyncMeta) -> [CloudRow<T>] {
    var live: [String: T] = [:]
    for i in items { live[i.id] = i }
    return ids.compactMap { id in
        guard let stamp = meta.stamp[id] else { return nil }
        if let deletedAt = meta.tombstone[id] {
            return CloudRow(id: id, data: nil, updated_at: stamp, deleted_at: deletedAt)
        }
        guard let item = live[id] else { return nil }
        return CloudRow(id: id, data: item, updated_at: stamp, deleted_at: nil)
    }
}

// MARK: - Merge

struct MergeOutcome {
    /// Ids removed from the live array because the cloud says they were deleted.
    var deletedIds: [String] = []
    /// Anything at all changed locally.
    var changed: Bool { !deletedIds.isEmpty || appliedCount > 0 }
    var appliedCount: Int = 0
    /// Rows where the server turned out to hold an OLDER copy than ours; ours was marked
    /// dirty again so the next push repairs the server. See mergeRows.
    var healedCount: Int = 0
}

/// Merge a delta pull into local state. Pure w.r.t. the network; mutates `items`/`meta`.
///
/// Ordering is by row stamp, and *only* by row stamp:
///   • incoming strictly newer  → it wins (a live row replaces, a tombstone deletes)
///   • incoming strictly older  → local wins; it stays dirty and pushes on the next cycle
///   • exact tie               → a delete wins, an edit does not
///
/// The tie rule is the whole point. The original bug — delete on Mac, reminder returns —
/// is the case where the iPhone's live copy carries an *older* stamp than the Mac's
/// tombstone, so the delete holds. But an un-delete (Undo) stamps strictly newer than the
/// tombstone it revives, so it wins. "Delete beats edit" is really "later intent wins,
/// ties go to the delete" — the absolute version in the design doc would have made
/// `undoDelete()` silently self-revert on the other device's next pull.
///
/// An id absent from a delta pull is NOT a deletion; a pull is a delta, not a census.
@discardableResult
func mergeRows<T: SyncItem>(_ rows: [CloudRow<T>], into items: inout [T], meta: inout SyncMeta) -> MergeOutcome {
    var out = MergeOutcome()
    var index: [String: Int] = [:]
    for (i, item) in items.enumerated() { index[item.id] = i }
    var removals = Set<String>()

    for row in rows {
        let k = row.id
        if let c = meta.cursor { if row.updated_at > c { meta.cursor = row.updated_at } }
        else { meta.cursor = row.updated_at }

        let local = meta.stamp[k]
        let incomingWins: Bool
        if let local {
            if row.updated_at > local { incomingWins = true }
            else if row.updated_at == local { incomingWins = (row.deleted_at != nil) }
            else { incomingWins = false }
        } else {
            incomingWins = true          // never seen it; nothing to lose
        }
        guard incomingWins else {
            // HEAL (2026-10-18). The server holds an OLDER copy than the one we already
            // uploaded — another device's stale upload landed after ours (the server took the
            // last write, not the newest). Before this, we just skipped it: we kept our newer
            // copy, the server and the other device kept the old one, and nothing ever
            // reconciled them. Re-dirty ours so the next push puts the newer copy back.
            // (Server side, 06_reject_older_writes.sql now refuses such stale writes too.)
            if let local, row.updated_at < local, let pushed = meta.pushedSig[k], pushed == meta.sig[k] {
                meta.pushedSig.removeValue(forKey: k)
                out.healedCount += 1
            }
            continue
        }

        if let deletedAt = row.deleted_at {
            if index[k] != nil { removals.insert(k); out.deletedIds.append(k) }
            meta.tombstone[k] = deletedAt
            meta.stamp[k] = row.updated_at
            meta.sig[k] = tombSignature(deletedAt)
            meta.pushedSig[k] = meta.sig[k]      // it came from the cloud; nothing to push
            out.appliedCount += 1
        } else if let item = row.data {
            if let i = index[k] { items[i] = item } else { items.append(item); index[k] = items.count - 1 }
            meta.tombstone.removeValue(forKey: k)   // a newer live row revives a tombstone
            meta.stamp[k] = row.updated_at
            meta.sig[k] = liveSignature(item)
            meta.pushedSig[k] = meta.sig[k]
            out.appliedCount += 1
        }
        // A row with neither data nor deleted_at is malformed; ignore it.
    }

    if !removals.isEmpty {
        items.removeAll { removals.contains($0.id) }
    }
    return out
}

// MARK: - REST

enum SyncTable: String {
    case reminders, lists, smart_lists
}

/// Thin PostgREST client for the four per-item tables. Every call returns the HTTP status
/// so the caller can do the existing refresh-token-once-on-401 dance.
enum CloudAPI {
    private static func request(_ path: String, method: String = "GET") -> URLRequest? {
        guard let u = URL(string: "\(Secrets.supabaseURL)/rest/v1/\(path)") else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = method
        r.setValue(Secrets.supabaseAnon, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(Auth.bearer())", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    /// Rows changed since `cursor`. A nil cursor pulls everything (fresh install).
    ///
    /// The cursor is rewound by a small margin before filtering: two devices' clocks are
    /// NTP-synced but not identical, and a row written a few hundred ms "in the past"
    /// relative to our cursor would otherwise never be seen again. Re-pulling a handful of
    /// rows is free — `mergeRows` is idempotent (an equal stamp on a live row is a no-op).
    ///
    /// PAGED (2026-10-18). Supabase caps a single response (1000 rows by default), and this
    /// used to ask for everything in one request with no order. Tombstones stay in the table,
    /// so a fresh install / cleared cache could silently receive only part of the rows — and
    /// with the cursor set from that partial set, never fetch the rest. Pages are ordered by
    /// `id` (stable: an edit never moves a row) and fetched until an EMPTY page, rather than a
    /// short one, so a server cap smaller than our page size can't end the loop early either.
    static func pull<T: SyncItem>(_ table: SyncTable, since cursor: String?, as: T.Type) async -> (rows: [CloudRow<T>]?, status: Int) {
        var base = "\(table.rawValue)?select=id,data,updated_at,deleted_at&order=id.asc"
        if let c = cursor, let rewound = rewind(c) {
            base += "&updated_at=gt.\(rewound)"
        }
        var all: [CloudRow<T>] = []
        var offset = 0
        var lastCode = 200
        while true {
            guard let req = request(base + "&limit=\(pageSize)&offset=\(offset)") else { return (nil, -1) }
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else { return (nil, code) }
                lastCode = code
                let page = try JSONDecoder().decode([CloudRow<T>].self, from: data)
                if page.isEmpty { return (all, lastCode) }
                all += page
                offset += page.count
                if offset >= maxRows { return (all, lastCode) }   // runaway guard
            } catch { return (nil, -1) }
        }
    }

    private static let pageSize = 1000
    private static let maxRows = 200_000

    /// Batch upsert. One request per table, not one per row.
    static func push<T: SyncItem>(_ table: SyncTable, rows: [CloudRow<T>]) async -> Int {
        guard !rows.isEmpty else { return 200 }
        guard var req = request("\(table.rawValue)?on_conflict=user_id,id", method: "POST") else { return -1 }
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        guard let body = try? JSONEncoder().encode(rows) else { return -1 }
        req.httpBody = body
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch { return -1 }
    }

    private static let clockSkewMargin: TimeInterval = 120

    private static func rewind(_ cursor: String) -> String? {
        guard let d = stampFormatter.date(from: cursor) else { return nil }
        return syncStamp(d.addingTimeInterval(-clockSkewMargin))
    }
}

// MARK: - Settings (single row, whole-value)

/// `settings` has no per-item identity, so it stays a single row merged as a whole on its
/// stamp. It is small, low-churn, and effectively write-once — nothing in the app mutates
/// it today; it is round-tripped so the (retired) web client's preferences survive.
struct SettingsRow: Codable {
    var data: [String: JSONValue]?
    var updated_at: String
}

extension CloudAPI {
    static func pullSettings() async -> (row: SettingsRow?, status: Int) {
        guard let req = request("settings?select=data,updated_at") else { return (nil, -1) }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { return (nil, code) }
            return (try JSONDecoder().decode([SettingsRow].self, from: data).first, code)
        } catch { return (nil, -1) }
    }

    static func pushSettings(_ row: SettingsRow) async -> Int {
        guard var req = request("settings?on_conflict=user_id", method: "POST") else { return -1 }
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        guard let body = try? JSONEncoder().encode([row]) else { return -1 }
        req.httpBody = body
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch { return -1 }
    }
}
