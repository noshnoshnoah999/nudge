import Foundation

// parseDate lives in NudgeStore.swift (app target); reproduce it verbatim here.
private let isoWithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
private let isoPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
}()
func parseDate(_ s: String?) -> Date? {
    guard let s = s, !s.isEmpty else { return nil }
    return isoWithFraction.date(from: s) ?? isoPlain.date(from: s)
}

var failures = 0
func check(_ label: String, _ cond: Bool) {
    print((cond ? "  ok   " : "  FAIL ") + label)
    if !cond { failures += 1 }
}

func mk(_ id: String, _ title: String, updatedAt: String? = nil) -> Reminder {
    Reminder(id: id, title: title, updatedAt: updatedAt)
}

let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ secs: TimeInterval) -> String { syncStamp(t0.addingTimeInterval(secs)) }

// ---------------------------------------------------------------------------
print("\n1. THE ORIGINAL BUG: delete on Mac must stay deleted on the Mac.")
// Mac deletes r1 at t=100. iPhone still holds r1 (last edited t=50) and pushes it.
// The Mac then pulls. Under the old blob model the reminder reappeared.
do {
    var items = [mk("r1", "Buy milk", updatedAt: at(50))]
    var meta = seedMigratedMeta(items)
    // Mac-side delete:
    meta.tombstone["r1"] = at(100)
    items.removeAll { $0.id == "r1" }
    refreshSignatures(items, meta: &meta, now: t0.addingTimeInterval(100))

    // iPhone's stale live row arrives (its stamp is the older edit time).
    let incoming = [CloudRow(id: "r1", data: mk("r1", "Buy milk", updatedAt: at(50)), updated_at: at(50), deleted_at: nil)]
    mergeRows(incoming, into: &items, meta: &meta)

    check("stale live row does not resurrect the deleted reminder", items.isEmpty)
    check("tombstone survives the merge", meta.tombstone["r1"] != nil)
    check("tombstone is still dirty, so it will push to the iPhone", dirtyIds(meta) == ["r1"])
    let rows = dirtyRows(dirtyIds(meta), items: items, meta: meta)
    check("pushed row carries deleted_at", rows.first?.deleted_at != nil && rows.first?.data == nil)
}

// ---------------------------------------------------------------------------
print("\n2. DELETE BEATS A CONCURRENT (older) EDIT.")
do {
    var items = [mk("r1", "edited on this device", updatedAt: at(40))]
    var meta = seedMigratedMeta(items)
    refreshSignatures(items, meta: &meta, now: t0.addingTimeInterval(40))
    // Other device deleted it later.
    mergeRows([CloudRow<Reminder>(id: "r1", data: nil, updated_at: at(90), deleted_at: at(90))],
              into: &items, meta: &meta)
    check("newer tombstone removes the locally-edited item", items.isEmpty)
    check("nothing left to push (we accepted the cloud's delete)", dirtyIds(meta).isEmpty)
}

print("\n   ...and an exact tie also goes to the delete.")
do {
    var items = [mk("r1", "x", updatedAt: at(40))]
    var meta = seedMigratedMeta(items)
    let stamp = meta.stamp["r1"]!
    mergeRows([CloudRow<Reminder>(id: "r1", data: nil, updated_at: stamp, deleted_at: stamp)],
              into: &items, meta: &meta)
    check("tie -> delete wins", items.isEmpty && meta.tombstone["r1"] != nil)
}

// ---------------------------------------------------------------------------
print("\n3. UNDO SURVIVES. (The design doc's absolute 'delete always wins' broke this.)")
do {
    var items = [mk("r1", "Buy milk", updatedAt: at(50))]
    var meta = seedMigratedMeta(items)

    // Delete, then immediately Undo — same millisecond, worst case.
    let now = t0.addingTimeInterval(100)
    meta.tombstone["r1"] = syncStamp(now)
    items.removeAll { $0.id == "r1" }
    refreshSignatures(items, meta: &meta, now: now)
    let tombStamp = meta.stamp["r1"]!

    meta.tombstone.removeValue(forKey: "r1")          // undoDelete()
    items.append(mk("r1", "Buy milk", updatedAt: syncStamp(now)))
    refreshSignatures(items, meta: &meta, now: now)   // same instant

    check("revived stamp is STRICTLY newer than its own tombstone", meta.stamp["r1"]! > tombStamp)

    // Now the tombstone we already pushed comes back at us from the other device.
    mergeRows([CloudRow<Reminder>(id: "r1", data: nil, updated_at: tombStamp, deleted_at: tombStamp)],
              into: &items, meta: &meta)
    check("the already-pushed tombstone does NOT re-delete it", items.count == 1)
    check("revival is dirty and will propagate", dirtyIds(meta) == ["r1"])
}

// ---------------------------------------------------------------------------
print("\n4. CONCURRENT EDITS: newer wins, per item, without touching its neighbours.")
do {
    var items = [mk("r1", "local newer", updatedAt: at(90)), mk("r2", "untouched", updatedAt: at(10))]
    var meta = seedMigratedMeta(items)
    mergeRows([CloudRow(id: "r1", data: mk("r1", "cloud older", updatedAt: at(30)), updated_at: at(30), deleted_at: nil)],
              into: &items, meta: &meta)
    check("older cloud row loses", items.first { $0.id == "r1" }?.title == "local newer")

    mergeRows([CloudRow(id: "r1", data: mk("r1", "cloud newer", updatedAt: at(99)), updated_at: at(99), deleted_at: nil)],
              into: &items, meta: &meta)
    check("newer cloud row wins", items.first { $0.id == "r1" }?.title == "cloud newer")
    check("the untouched neighbour is untouched", items.first { $0.id == "r2" }?.title == "untouched")
    check("an item we adopted from the cloud is not dirty", !dirtyIds(meta).contains("r1"))
}

// ---------------------------------------------------------------------------
print("\n5. A DELTA PULL IS NOT A CENSUS: absence never deletes.")
do {
    var items = [mk("r1", "only on this device", updatedAt: at(10))]
    var meta = seedMigratedMeta(items)
    mergeRows([CloudRow<Reminder>](), into: &items, meta: &meta)
    check("empty pull leaves local items alone", items.count == 1)
}

// ---------------------------------------------------------------------------
print("\n6. MIGRATION SEED: adopting the old blob marks nothing dirty.")
do {
    let items = [mk("r1", "a", updatedAt: at(10)), mk("r2", "b", updatedAt: nil)]
    var meta = seedMigratedMeta(items)
    check("no spurious first-launch push", dirtyIds(meta).isEmpty)
    check("null updatedAt seeds to epoch, so any real edit outranks it", meta.stamp["r2"] == epochStamp)
    // A genuine local edit afterwards does become dirty.
    var edited = items
    edited[0].title = "a!"
    refreshSignatures(edited, meta: &meta, now: t0.addingTimeInterval(200))
    check("a real edit is detected with no mutation-site bookkeeping", dirtyIds(meta) == ["r1"])
}

// ---------------------------------------------------------------------------
print("\n7. BACKFILL CASE: content changes WITHOUT updatedAt moving must still sync.")
do {
    // backfillFromApple() rewrites recurrence/url and deliberately leaves updatedAt alone.
    var items = [mk("r1", "Water plants", updatedAt: at(10))]
    var meta = seedMigratedMeta(items)
    items[0].url = "https://example.com"          // updatedAt untouched, on purpose
    refreshSignatures(items, meta: &meta, now: t0.addingTimeInterval(300))
    check("content hash catches it even though updatedAt is unchanged", dirtyIds(meta) == ["r1"])
    check("row stamp advances so the other device pulls it", meta.stamp["r1"]! > at(10))
    check("the item's own updatedAt is left alone (Apple tiebreak intact)", items[0].updatedAt == at(10))
}

// ---------------------------------------------------------------------------
print("\n8. ROW ENCODING: nils must be explicit JSON nulls.")
do {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let live = CloudRow(id: "r1", data: mk("r1", "x"), updated_at: at(0), deleted_at: nil)
    let s = String(data: try! enc.encode(live), encoding: .utf8)!
    check("a live row explicitly nulls deleted_at (else upsert keeps the old tombstone)",
          s.contains("\"deleted_at\":null"))
    let tomb = CloudRow<Reminder>(id: "r1", data: nil, updated_at: at(0), deleted_at: at(0))
    let s2 = String(data: try! enc.encode(tomb), encoding: .utf8)!
    check("a tombstone row explicitly nulls data", s2.contains("\"data\":null"))
}

// ---------------------------------------------------------------------------
print("\n9. STAMPS: fixed-width, so lexicographic order == chronological order.")
do {
    let a = syncStamp(Date(timeIntervalSince1970: 1_700_000_000.0))
    let b = syncStamp(Date(timeIntervalSince1970: 1_700_000_000.5))
    check("all stamps are the same width", a.count == b.count && a.count == 24)
    check("string order matches time order", a < b)
    check("plain ISO normalises to the canonical form", normalizeStamp("2023-11-14T22:13:20Z") == a)
    check("stamp(after:) steps past a stamp from the future",
          syncStamp(after: at(10_000), at: t0) > at(10_000))
}

print("\n\(failures == 0 ? "ALL PASSED" : "\(failures) FAILURE(S)")")
exit(failures == 0 ? 0 : 1)
