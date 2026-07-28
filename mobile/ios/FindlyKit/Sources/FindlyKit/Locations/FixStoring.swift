import Foundation

/// A frozen, retryable batch: `batchId` + the exact `fixes` it was created with. specs/001 §5.1:
/// "A `batchId` permanently identifies a frozen set of fixes." Lives here (not `FixQueue.swift`)
/// because it is now, first and foremost, a **storage** shape — see `FixStoring`'s doc below.
public struct PendingBatch: Equatable {
    public let batchId: String
    public let fixes: [LocationFix]
}

/// Persistence for the offline fix-queue (specs/004-ios-client.md §6, specs/009-device-runtime.md
/// §2). Widened from I1's `loadAll`/`append`/`remove` shape to also own the **frozen in-flight
/// batch's identity** — this is the fix for the exact durability gap specs/009 §2 calls out:
///
/// > "the durable queue MUST... persist the in-flight `PendingBatch` (`batchId` + frozen fix set)
/// > so a retry after a crash resends identical content."
///
/// Before this widening, `batchId`/the frozen fix set lived only in `FixQueue`'s own in-memory
/// `inFlight` property — invisible to whatever `FixStoring` implementation was plugged in, and
/// therefore gone on process death even once `InMemoryFixStore` was swapped for a real on-disk
/// store (swapping the *fix rows'* persistence alone does nothing for the *batch identity*
/// sitting next to them in actor memory). Mirrors Android's `FixEntity.batchId` / `FixQueueDao`
/// split exactly (`queue/room/FixEntity.kt`, `queue/room/FixQueueDao.kt`, specs/009 §2's rationale
/// comment there): storing `batchId` **on the fix row itself**, assigned in the same atomic
/// operation that reads the rows to freeze, is what makes "batch identity" and "the exact fix set"
/// durable as one unit — a conforming implementation (see `SQLiteFixStore`) MUST perform
/// `freezeNextBatch`/`markAccepted`/`markRejected` each as a single atomic transaction, exactly as
/// `RoomFixQueueStore`'s `@Transaction` DAO methods do.
///
/// `FixQueue` (the actor above this protocol) holds **no in-memory bookkeeping of its own** any
/// more — every method reads fresh from a `FixStoring` implementation, so a freshly-constructed
/// `FixQueue`/store pair after a process restart sees exactly the same in-flight batch (if any) a
/// pre-crash instance would have. `InMemoryFixStore` is the test/default implementation (I1);
/// `SQLiteFixStore` is the durable, on-disk implementation (specs/009 §2) that replaces it for a
/// real device build behind this *unchanged* protocol.
public protocol FixStoring {
    /// All fixes currently in the store — pending **and** frozen-in-flight alike — in insertion
    /// order. Mirrors `RoomFixQueueDao.pendingCount()`'s "everything not yet resolved" semantics.
    func loadAll() -> [LocationFix]

    /// Appends one pending (unfrozen) fix, then enforces the 1 000-fix cap (specs/009 §2): when
    /// the total row count exceeds `cap`, the **oldest not-yet-frozen** fixes are dropped first —
    /// an in-flight frozen batch is never touched by the cap. Returns the number of fixes dropped
    /// (0 if none) so a caller can log a **count-only** debug line (never coordinates,
    /// docs/security-review-checklist.md).
    @discardableResult
    func append(_ fix: LocationFix) -> Int

    /// Removes fixes by id regardless of frozen state (specs/008-privacy-endpoints.md §4.4 local
    /// wipe uses this via `removeAll`; also available for direct id-based removal).
    func remove(fixIds: Set<String>)

    /// The currently frozen in-flight batch, if any — read fresh from storage on every call (the
    /// property specs/009 §2 exists for: "so a retry after a crash resends identical content").
    func currentBatch() -> PendingBatch?

    /// Freeze-on-first-ask (specs/001 §5.1 rule 1, specs/004 §6): returns the existing in-flight
    /// batch **unchanged** if one exists (never reassigns, never mints a second in-flight batch);
    /// otherwise freezes the oldest `≤ maxSize` pending fixes atomically under a fresh `batchId`
    /// from `newBatchId`. `nil` when nothing is pending. A conforming implementation MUST perform
    /// the "read pending, assign batchId to those exact rows" sequence as one atomic operation —
    /// see this file's top doc.
    func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> PendingBatch?

    /// Any 2xx (incl. a duplicate-replay 200): permanently removes exactly the named batch's
    /// fixes. A no-op if `batchId` doesn't match anything currently frozen.
    func markAccepted(batchId: String)

    /// Any definitive 4xx: drops `dropFixIds` (or every fix in the batch when `nil`) and
    /// un-freezes the remainder (clears `batchId` on the surviving rows) so it is eligible for a
    /// **new** `batchId` on the next `freezeNextBatch` call — never the dead one. A no-op if
    /// `batchId` doesn't match anything currently frozen.
    func markRejected(batchId: String, dropFixIds: Set<String>?)

    /// Drops every row unconditionally, pending and frozen alike (specs/008-privacy-endpoints.md
    /// §4.4 local-state wipe).
    func removeAll()
}

/// The in-memory `FixStoring` implementation — I1's original default, now reimplemented against
/// the widened protocol above so its behavior is a faithful (just non-durable) mirror of
/// `SQLiteFixStore`: exactly the same freeze/accept/reject/cap semantics, minus surviving process
/// death. Remains `FixQueue`'s default store for tests (`swift test` never needs a real file).
public final class InMemoryFixStore: FixStoring {
    /// `nil` batchId = pending; non-nil = frozen into that in-flight batch. Order in this array IS
    /// insertion order — mirrors `FixEntity.seq` without needing an explicit counter.
    private var rows: [(fix: LocationFix, batchId: String?)] = []
    private let cap: Int
    private let onOverflowDropped: (Int) -> Void

    public init(cap: Int = 1000, onOverflowDropped: @escaping (Int) -> Void = { _ in }) {
        self.cap = cap
        self.onOverflowDropped = onOverflowDropped
    }

    public func loadAll() -> [LocationFix] { rows.map(\.fix) }

    @discardableResult
    public func append(_ fix: LocationFix) -> Int {
        rows.append((fix, nil))
        let overflow = rows.count - cap
        guard overflow > 0 else { return 0 }
        let pendingIndices = rows.indices.filter { rows[$0].batchId == nil }
        let toDrop = Set(pendingIndices.prefix(overflow))
        guard !toDrop.isEmpty else { return 0 }
        rows = rows.enumerated().filter { !toDrop.contains($0.offset) }.map(\.element)
        onOverflowDropped(toDrop.count)
        return toDrop.count
    }

    public func remove(fixIds: Set<String>) {
        rows.removeAll { fixIds.contains($0.fix.fixId) }
    }

    public func currentBatch() -> PendingBatch? {
        guard let batchId = rows.first(where: { $0.batchId != nil })?.batchId else { return nil }
        return PendingBatch(batchId: batchId, fixes: rows.filter { $0.batchId == batchId }.map(\.fix))
    }

    public func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> PendingBatch? {
        if let existing = currentBatch() { return existing }
        let pendingIndices = rows.indices.filter { rows[$0].batchId == nil }
        guard !pendingIndices.isEmpty else { return nil }
        let sliceIndices = pendingIndices.prefix(maxSize)
        let batchId = newBatchId()
        for index in sliceIndices { rows[index].batchId = batchId }
        return PendingBatch(batchId: batchId, fixes: sliceIndices.map { rows[$0].fix })
    }

    public func markAccepted(batchId: String) {
        rows.removeAll { $0.batchId == batchId }
    }

    public func markRejected(batchId: String, dropFixIds: Set<String>?) {
        let idsToDrop = dropFixIds ?? Set(rows.filter { $0.batchId == batchId }.map(\.fix.fixId))
        rows.removeAll { idsToDrop.contains($0.fix.fixId) }
        for index in rows.indices where rows[index].batchId == batchId {
            rows[index].batchId = nil
        }
    }

    public func removeAll() {
        rows.removeAll()
    }
}
