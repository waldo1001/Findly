import Foundation

/// A frozen, retryable batch of geofence events — mirrors `PendingBatch`'s freeze-on-first-ask
/// shape (specs/009-device-runtime.md §6.3: "Events are flushed like fixes, batched 1-20 per
/// call"). `batchId` is a **client-local grouping only** — never sent over the wire (001-api-
/// contract.md §7.3's request body has no `batchId` field); it exists purely so a transient-failure
/// retry resends the identical event set, mirroring Android's `GeofenceEventBatch`.
public struct GeofenceEventBatch: Equatable {
    public let batchId: String
    public let events: [GeofenceEventReport]

    public init(batchId: String, events: [GeofenceEventReport]) {
        self.batchId = batchId
        self.events = events
    }
}

/// Persistence for the durable geofence-event queue (specs/009-device-runtime.md §6.3) — deliberately
/// mirrors `FixStoring`'s freeze-on-first-ask shape so a transient flush failure retries the exact
/// same batch, even though the wire idempotency key here is per-event (`eventId`, 001-api-
/// contract.md §7.3) rather than per-batch like `POST /locations`' `batchId`. There is no
/// server-defined per-event rejection shape to react to (unlike `FixStoring.markRejected`'s
/// `dropFixIds`) — every non-`TRACKING_PAUSED` failure just retries the whole batch, so this
/// protocol has no reject method, only `markSent`/`markFailedTransient`. `SQLiteGeofenceEventQueueStore`
/// is the durable, on-disk implementation (same durability bar as `SQLiteFixStore`, specs/009 §2)
/// that replaces `InMemoryGeofenceEventQueueStore` for a real device build behind this unchanged
/// protocol. Mirrors Android's `GeofenceEventQueueStore`.
public protocol GeofenceEventQueueStoring {
    /// All events currently in the store — pending **and** frozen-in-flight alike — in insertion
    /// order.
    func loadAll() -> [GeofenceEventReport]

    /// Appends one pending (unfrozen) event. Unlike `FixStoring.append`, there is no overflow cap
    /// (not specified for events, unlike the fix queue's explicit 1 000 cap, specs/009 §2) — a
    /// detected transition MUST NOT be silently dropped for capacity reasons (§6.3 treats a lost
    /// transition as a MUST-not, unlike a dropped mid-GPS-capture fix).
    func enqueue(_ event: GeofenceEventReport)

    /// The currently frozen in-flight batch, if any — read fresh from storage on every call, same
    /// durability property as `FixStoring.currentBatch()`.
    func currentBatch() -> GeofenceEventBatch?

    /// Freeze-on-first-ask: returns the existing in-flight batch **unchanged** if one exists,
    /// otherwise freezes the oldest `≤ maxSize` pending events atomically under a fresh `batchId`
    /// from `newBatchId`. `nil` when nothing is pending.
    func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> GeofenceEventBatch?

    /// Any 2xx response, regardless of the `accepted`/`duplicates` split (idempotent on `eventId`
    /// server-side, so a partially-duplicate batch is still fully resolved from the queue's point
    /// of view) — permanently removes exactly the named batch's events. A no-op if `batchId`
    /// doesn't match anything currently frozen.
    func markSent(batchId: String)

    /// Network error / 5xx / any other non-`TRACKING_PAUSED` failure — no-op on the pending pool;
    /// the batch stays frozen under the same id for an identical retry (no per-event rejection
    /// shape is defined for this endpoint, so there is nothing to drop). Kept as an explicit,
    /// named method (rather than callers doing nothing) so the "changes nothing" contract has one
    /// obvious home, matching `FixQueue.handleTransientFailure`'s precedent.
    func markFailedTransient(batchId: String)

    /// Drops every row unconditionally, pending and frozen alike (specs/008-privacy-endpoints.md
    /// §4.4 local-state wipe).
    func removeAll()
}

/// The in-memory `GeofenceEventQueueStoring` implementation — mirrors `InMemoryFixStore`'s
/// structure exactly (a faithful, just non-durable, mirror of `SQLiteGeofenceEventQueueStore`).
/// `GeofenceEventQueue`'s default store for tests (`swift test` never needs a real file).
public final class InMemoryGeofenceEventQueueStore: GeofenceEventQueueStoring {
    /// `nil` batchId = pending; non-nil = frozen into that in-flight batch. Order in this array IS
    /// insertion order.
    private var rows: [(event: GeofenceEventReport, batchId: String?)] = []

    public init() {}

    public func loadAll() -> [GeofenceEventReport] { rows.map(\.event) }

    public func enqueue(_ event: GeofenceEventReport) {
        rows.append((event, nil))
    }

    public func currentBatch() -> GeofenceEventBatch? {
        guard let batchId = rows.first(where: { $0.batchId != nil })?.batchId else { return nil }
        return GeofenceEventBatch(batchId: batchId, events: rows.filter { $0.batchId == batchId }.map(\.event))
    }

    public func freezeNextBatch(maxSize: Int, newBatchId: () -> String) -> GeofenceEventBatch? {
        if let existing = currentBatch() { return existing }
        let pendingIndices = rows.indices.filter { rows[$0].batchId == nil }
        guard !pendingIndices.isEmpty else { return nil }
        let sliceIndices = pendingIndices.prefix(maxSize)
        let batchId = newBatchId()
        for index in sliceIndices { rows[index].batchId = batchId }
        return GeofenceEventBatch(batchId: batchId, events: sliceIndices.map { rows[$0].event })
    }

    public func markSent(batchId: String) {
        rows.removeAll { $0.batchId == batchId }
    }

    public func markFailedTransient(batchId: String) {
        // Intentionally a no-op on the pending pool - see this method's protocol doc.
    }

    public func removeAll() {
        rows.removeAll()
    }
}
