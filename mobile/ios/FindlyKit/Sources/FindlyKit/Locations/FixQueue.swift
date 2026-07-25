import Foundation

/// A frozen, retryable batch: `batchId` + the exact `fixes` it was created with. specs/001 §5.1:
/// "A `batchId` permanently identifies a frozen set of fixes."
public struct PendingBatch: Equatable {
    public let batchId: String
    public let fixes: [LocationFix]
}

/// specs/004-ios-client.md §6, specs/001 §5.1, specs/000 §D7 — the offline fix-queue's
/// batch/idempotency model. An `actor` so concurrent enqueue (e.g. from a location callback) and
/// send (from a background task) are race-free.
public actor FixQueue {
    private let store: FixStoring
    private let generateBatchId: () -> String
    private var inFlight: PendingBatch?

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
    /// `fixes`), otherwise freezes up to `maxBatchSize` queued fixes into a new one. Fixes enqueued
    /// after freezing are never added to the in-flight batch — they wait for the next call after
    /// this one resolves (`handleAccepted`/`handleDefinitiveRejection`).
    public func nextBatchToSend(maxBatchSize: Int = 100) -> PendingBatch? {
        if let inFlight { return inFlight }
        let queued = store.loadAll()
        guard !queued.isEmpty else { return nil }
        let batch = PendingBatch(batchId: generateBatchId(), fixes: Array(queued.prefix(maxBatchSize)))
        inFlight = batch
        return batch
    }

    /// 2xx (including a duplicate-replay 200) — the batch's fixes are gone for good.
    public func handleAccepted(batchId: String) {
        guard let inFlight, inFlight.batchId == batchId else { return }
        store.remove(fixIds: Set(inFlight.fixes.map(\.fixId)))
        self.inFlight = nil
    }

    /// Network error or 5xx — no marker was written server-side either way here, but the point is
    /// retry safety: keep the in-flight batch's `batchId`/`fixes` completely unchanged so the next
    /// `nextBatchToSend` resends identical content.
    public func handleTransientFailure(batchId: String) {
        // Intentionally a no-op beyond validating the caller is talking about the current batch —
        // `inFlight` is left untouched either way, which is the entire point of this method
        // existing as a named, documented no-op rather than callers just doing nothing.
        _ = (inFlight?.batchId == batchId)
    }

    /// Any 4xx — per specs/001 §5.1, "no marker was written — the batch is dead." Drops the
    /// offending fixes (`dropFixIds`, mapped from `details.fields`) or the whole batch if the
    /// caller can't map fields, then clears in-flight so the remainder gets a **new** `batchId` on
    /// the next `nextBatchToSend` call — never the dead one.
    public func handleDefinitiveRejection(batchId: String, dropFixIds: Set<String>? = nil) {
        guard let inFlight, inFlight.batchId == batchId else { return }
        let idsToDrop = dropFixIds ?? Set(inFlight.fixes.map(\.fixId))
        store.remove(fixIds: idsToDrop)
        self.inFlight = nil
    }

    /// specs/008-privacy-endpoints.md §4.4, specs/004-ios-client.md §3.6 — account deletion's
    /// local-state wipe. Drops every queued fix AND any frozen in-flight batch, so a stale batch
    /// can never resurface a since-deleted user's fixes on the next `nextBatchToSend` call.
    public func clearAll() {
        store.remove(fixIds: Set(store.loadAll().map(\.fixId)))
        inFlight = nil
    }
}
