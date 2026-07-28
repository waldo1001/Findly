import Foundation

/// specs/009-device-runtime.md §6.3 — the geofence-event queue's batch/idempotency model,
/// deliberately mirroring `FixQueue`'s shape: an `actor` so concurrent enqueue (a region-monitoring
/// delegate callback) and send (the sync-runner drain) are race-free, holding **zero in-memory
/// bookkeeping of its own** — every method is a thin, stateless delegation to `store` (a
/// `GeofenceEventQueueStoring`), the single source of truth for both the pending events AND the
/// frozen in-flight batch's identity (so a process restart mid-flush resends identical content,
/// same durability property `FixQueue`/`SQLiteFixStore` establish for fixes).
public actor GeofenceEventQueue {
    private let store: GeofenceEventQueueStoring
    private let generateBatchId: () -> String

    public init(store: GeofenceEventQueueStoring = InMemoryGeofenceEventQueueStore(), generateBatchId: @escaping () -> String = { UUID().uuidString }) {
        self.store = store
        self.generateBatchId = generateBatchId
    }

    public func enqueue(_ event: GeofenceEventReport) {
        store.enqueue(event)
    }

    public func pendingCount() -> Int {
        store.loadAll().count
    }

    /// Returns the in-flight batch unchanged if one exists (a retry), otherwise freezes up to
    /// `maxBatchSize` queued events into a new one (default 20, 001-api-contract.md §7.3's per-call
    /// cap). Events recorded after freezing wait for the next batch.
    public func nextBatchToSend(maxBatchSize: Int = 20) -> GeofenceEventBatch? {
        store.freezeNextBatch(maxSize: maxBatchSize, newBatchId: generateBatchId)
    }

    /// Any 2xx (incl. a duplicate-replay 200, idempotent on `eventId`) — the batch's events are
    /// gone for good. Guarded against a stale/mismatched `batchId`, mirroring `FixQueue.handleAccepted`.
    public func handleSent(batchId: String) {
        guard store.currentBatch()?.batchId == batchId else { return }
        store.markSent(batchId: batchId)
    }

    /// Network error / 5xx / any other non-`TRACKING_PAUSED` failure — the in-flight batch's
    /// `batchId`/`events` stay completely unchanged, so the next `nextBatchToSend` resends
    /// identical content. Mirrors `FixQueue.handleTransientFailure`'s explicit no-op contract.
    public func handleTransientFailure(batchId: String) {
        _ = (store.currentBatch()?.batchId == batchId)
    }

    /// specs/008-privacy-endpoints.md §4.4, specs/004-ios-client.md §3.6 — account deletion's
    /// local-state wipe. Drops every queued event AND any frozen in-flight batch.
    public func clearAll() {
        store.removeAll()
    }
}
