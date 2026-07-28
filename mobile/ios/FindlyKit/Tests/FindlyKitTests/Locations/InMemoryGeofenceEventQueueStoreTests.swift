import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §6.3 — freeze-on-first-ask batching over the in-memory
/// `GeofenceEventQueueStoring`. Mirrors `InMemoryFixStoreTests`'s coverage shape (minus the cap,
/// which events don't have).
struct InMemoryGeofenceEventQueueStoreTests {

    func makeEvent(_ id: String, geofenceId: String = "gf_home", transition: GeofenceTransition = .enter) -> GeofenceEventReport {
        GeofenceEventReport(eventId: id, geofenceId: geofenceId, transition: transition, recordedAt: "2026-07-19T09:00:00Z")
    }

    @Test func loadAll_isEmptyForAFreshStore() {
        let store = InMemoryGeofenceEventQueueStore()
        #expect(store.loadAll().isEmpty)
    }

    @Test func enqueue_thenLoadAll_preservesInsertionOrder() {
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))

        #expect(store.loadAll().map(\.eventId) == ["e1", "e2"])
    }

    @Test func freezeNextBatch_freezesPendingEventsUnderAFreshBatchId() {
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))

        let batch = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })

        #expect(batch?.batchId == "batch-1")
        #expect(batch?.events.map(\.eventId) == ["e1", "e2"])
    }

    @Test func freezeNextBatch_calledAgain_returnsTheSameFrozenBatch_notANewOne() {
        var counter = 0
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        let first = store.freezeNextBatch(maxSize: 20, newBatchId: { counter += 1; return "batch-\(counter)" })
        store.enqueue(makeEvent("e2")) // recorded after freezing - must not join the in-flight batch

        let retry = store.freezeNextBatch(maxSize: 20, newBatchId: { counter += 1; return "batch-\(counter)" })

        #expect(first == retry)
        #expect(retry?.events.map(\.eventId) == ["e1"])
        #expect(counter == 1, "newBatchId must not be invoked on a retry")
    }

    @Test func freezeNextBatch_respectsMaxSize() {
        let store = InMemoryGeofenceEventQueueStore()
        for i in 0..<25 { store.enqueue(makeEvent("e\(i)")) }

        let batch = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })

        #expect(batch?.events.count == 20)
    }

    @Test func freezeNextBatch_nothingPending_returnsNil() {
        let store = InMemoryGeofenceEventQueueStore()
        #expect(store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" }) == nil)
    }

    @Test func currentBatch_reflectsTheFrozenBatchWithoutFreezingAgain() {
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        _ = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })

        #expect(store.currentBatch()?.batchId == "batch-1")
        #expect(store.currentBatch()?.events.map(\.eventId) == ["e1"])
    }

    @Test func markSent_removesExactlyThatBatchsEvents() {
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))
        let batch = store.freezeNextBatch(maxSize: 1, newBatchId: { "batch-1" })!
        // e2 is still pending (batch size 1) - markSent must not touch it.
        store.markSent(batchId: batch.batchId)

        #expect(store.currentBatch() == nil)
        #expect(store.loadAll().map(\.eventId) == ["e2"])
    }

    @Test func markFailedTransient_leavesTheBatchFrozenAndUnchanged() {
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        let batch = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })!

        store.markFailedTransient(batchId: batch.batchId)

        #expect(store.currentBatch() == batch)
    }

    @Test func removeAll_wipesPendingAndFrozenEventsAlike() {
        let store = InMemoryGeofenceEventQueueStore()
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))
        _ = store.freezeNextBatch(maxSize: 1, newBatchId: { "batch-1" })

        store.removeAll()

        #expect(store.loadAll().isEmpty)
        #expect(store.currentBatch() == nil)
    }
}
