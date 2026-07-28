import Foundation

/// specs/004-ios-client.md §6, specs/001 §5.1, specs/000 §D7, specs/009-device-runtime.md §2 — the
/// offline fix-queue's batch/idempotency model. An `actor` so concurrent enqueue (e.g. from a
/// location callback) and send (from a background task) are race-free.
///
/// specs/009 §2 (I10): this actor now holds **zero in-memory bookkeeping of its own** — every
/// method is a thin, stateless delegation to `store` (a `FixStoring`), which is the single source
/// of truth for both the pending fixes AND the frozen in-flight batch's identity. Previously
/// `inFlight: PendingBatch?` lived here as a private `actor` property; that made the batch
/// identity invisible to whatever `FixStoring` was plugged in, so it never survived a process
/// restart even once the *fix rows* moved to durable storage — exactly the gap specs/009 §2 calls
/// out ("MUST persist the in-flight PendingBatch... so a retry after a crash resends identical
/// content"). Moving the bookkeeping into `store` (see `FixStoring`'s doc, and `SQLiteFixStore` for
/// the durable implementation) fixes that without changing this actor's external behavior at all —
/// every rule below (freeze-on-first-send, retry-same-batchId, accept-clears,
/// definitive-rejection-issues-a-new-id) is unchanged; only *where* the bookkeeping physically
/// lives changed. This mirrors Android's `RoomFixQueueStore`, which "deliberately holds no
/// in-memory state of its own... every method derives its answer fresh from the DAO."
public actor FixQueue {
    private let store: FixStoring
    private let generateBatchId: () -> String

    public init(store: FixStoring = InMemoryFixStore(), generateBatchId: @escaping () -> String = { UUID().uuidString }) {
        self.store = store
        self.generateBatchId = generateBatchId
    }

    public func enqueue(_ fix: LocationFix) {
        store.append(fix)
    }

    public func queuedCount() -> Int {
        store.loadAll().count
    }

    /// Returns the in-flight batch unchanged if one exists (a retry — same `batchId`, same frozen
    /// `fixes`), otherwise freezes up to `maxBatchSize` queued fixes into a new one. Fixes recorded
    /// after freezing are never added to that batch — they wait for the next one (queue > 100
    /// splits across multiple sequential batches, oldest first). Delegates entirely to
    /// `store.freezeNextBatch`, whose doc explains why this MUST be atomic in a durable
    /// implementation.
    public func nextBatchToSend(maxBatchSize: Int = 100) -> PendingBatch? {
        store.freezeNextBatch(maxSize: maxBatchSize, newBatchId: generateBatchId)
    }

    /// 2xx (including a duplicate-replay 200) — the batch's fixes are gone for good. Guarded
    /// against a stale/mismatched `batchId` (a caller resolving a batch that isn't the currently
    /// frozen one is a programming error, not a legitimate race) before delegating to the store.
    public func handleAccepted(batchId: String) {
        guard store.currentBatch()?.batchId == batchId else { return }
        store.markAccepted(batchId: batchId)
    }

    /// Network error or 5xx — no marker was written server-side either way here, but the point is
    /// retry safety: the in-flight batch's `batchId`/`fixes` stay completely unchanged (they
    /// already do — the store's `currentBatch()` was never touched) so the next `nextBatchToSend`
    /// resends identical content. Kept as an explicit, named no-op method (rather than callers
    /// just doing nothing) so the "changes nothing" contract has one obvious home.
    public func handleTransientFailure(batchId: String) {
        _ = (store.currentBatch()?.batchId == batchId)
    }

    /// Any 4xx — per specs/001 §5.1, "no marker was written — the batch is dead." Drops the
    /// offending fixes (`dropFixIds`, mapped from `details.fields`) or the whole batch if the
    /// caller can't map fields, then un-freezes the remainder so it gets a **new** `batchId` on the
    /// next `nextBatchToSend` call — never the dead one. Guarded the same way as `handleAccepted`.
    public func handleDefinitiveRejection(batchId: String, dropFixIds: Set<String>? = nil) {
        guard store.currentBatch()?.batchId == batchId else { return }
        store.markRejected(batchId: batchId, dropFixIds: dropFixIds)
    }

    /// specs/008-privacy-endpoints.md §4.4, specs/004-ios-client.md §3.6 — account deletion's
    /// local-state wipe. Drops every queued fix AND any frozen in-flight batch, so a stale batch
    /// can never resurface a since-deleted user's fixes on the next `nextBatchToSend` call.
    public func clearAll() {
        store.removeAll()
    }
}
