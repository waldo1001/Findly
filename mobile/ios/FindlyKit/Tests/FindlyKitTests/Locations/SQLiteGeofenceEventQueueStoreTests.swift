import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §6.3 — the durable, SQLite-backed `GeofenceEventQueueStoring`. The
/// most important test here is `survivesSimulatedProcessDeath...`, mirroring
/// `SQLiteFixStoreTests`'s own: proves the in-flight batch identity + exact event set survive a
/// process restart, since a region-monitoring delegate callback can fire after an app
/// relaunch-from-termination with no durable state yet in memory (specs/009 §3.4's relaunch
/// behavior applies identically to region transitions).
struct SQLiteGeofenceEventQueueStoreTests {

    func makeEvent(_ id: String, geofenceId: String = "gf_home", transition: GeofenceTransition = .enter) -> GeofenceEventReport {
        GeofenceEventReport(eventId: id, geofenceId: geofenceId, transition: transition, recordedAt: "2026-07-19T09:00:00Z")
    }

    func tempDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("findly-geofence-events-test-\(UUID().uuidString).sqlite")
    }

    // MARK: - Basic durability plumbing

    @Test func loadAll_isEmptyForAFreshDatabase() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        #expect(store.loadAll().isEmpty)
    }

    @Test func enqueue_thenLoadAll_preservesInsertionOrder() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))
        store.enqueue(makeEvent("e3"))

        #expect(store.loadAll().map(\.eventId) == ["e1", "e2", "e3"])
    }

    @Test func enqueue_preservesGeofenceIdAndTransition() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1", geofenceId: "gf_school", transition: .exit))

        let loaded = store.loadAll().first
        #expect(loaded?.geofenceId == "gf_school")
        #expect(loaded?.transition == .exit)
    }

    // MARK: - Freeze-on-first-ask (specs/009 §6.3)

    @Test func freezeNextBatch_freezesPendingEventsUnderAFreshBatchId() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))

        let batch = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })

        #expect(batch?.batchId == "batch-1")
        #expect(batch?.events.map(\.eventId) == ["e1", "e2"])
    }

    @Test func freezeNextBatch_calledAgain_returnsTheSameFrozenBatch_notANewOne() throws {
        var counter = 0
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        let first = store.freezeNextBatch(maxSize: 20, newBatchId: { counter += 1; return "batch-\(counter)" })
        store.enqueue(makeEvent("e2")) // recorded after freezing - must not join the in-flight batch

        let retry = store.freezeNextBatch(maxSize: 20, newBatchId: { counter += 1; return "batch-\(counter)" })

        #expect(first == retry)
        #expect(retry?.events.map(\.eventId) == ["e1"])
        #expect(counter == 1, "newBatchId must not be invoked on a retry")
    }

    @Test func freezeNextBatch_nothingPending_returnsNil() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        #expect(store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" }) == nil)
    }

    @Test func currentBatch_reflectsTheFrozenBatchWithoutFreezingAgain() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        _ = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })

        #expect(store.currentBatch()?.batchId == "batch-1")
        #expect(store.currentBatch()?.events.map(\.eventId) == ["e1"])
    }

    @Test func markSent_removesExactlyThatBatchsEvents() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))
        let batch = store.freezeNextBatch(maxSize: 1, newBatchId: { "batch-1" })!
        store.markSent(batchId: batch.batchId)

        #expect(store.currentBatch() == nil)
        #expect(store.loadAll().map(\.eventId) == ["e2"])
    }

    @Test func markFailedTransient_leavesTheBatchFrozenAndUnchanged() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        let batch = store.freezeNextBatch(maxSize: 20, newBatchId: { "batch-1" })!

        store.markFailedTransient(batchId: batch.batchId)

        #expect(store.currentBatch() == batch)
    }

    @Test func removeAll_wipesPendingAndFrozenEventsAlike() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))
        store.enqueue(makeEvent("e2"))
        _ = store.freezeNextBatch(maxSize: 1, newBatchId: { "batch-1" })

        store.removeAll()

        #expect(store.loadAll().isEmpty)
        #expect(store.currentBatch() == nil)
    }

    // MARK: - The central correctness property (specs/009 §6.3/§2's durability bar): survives
    // simulated process death

    @Test func survivesSimulatedProcessDeath_inFlightBatchIdentityAndEventSetAreIntactAfterReopening() throws {
        let url = tempDatabaseURL()
        let batchId: String
        let frozenEventIds: [String]
        do {
            let storeBeforeCrash = try SQLiteGeofenceEventQueueStore(url: url)
            storeBeforeCrash.enqueue(makeEvent("e1"))
            storeBeforeCrash.enqueue(makeEvent("e2"))
            storeBeforeCrash.enqueue(makeEvent("e3"))
            let frozen = storeBeforeCrash.freezeNextBatch(maxSize: 20, newBatchId: { "batch-before-crash" })!
            batchId = frozen.batchId
            frozenEventIds = frozen.events.map(\.eventId)
            storeBeforeCrash.enqueue(makeEvent("e4")) // recorded after the freeze - must survive as pending
        }
        let storeAfterRestart = try SQLiteGeofenceEventQueueStore(url: url)

        let recovered = storeAfterRestart.currentBatch()
        #expect(recovered?.batchId == batchId, "the in-flight batchId must survive process death unchanged")
        #expect(recovered?.events.map(\.eventId) == frozenEventIds, "the exact frozen event set must survive, in the same order")

        var mintedFreshBatchId = false
        let afterRestartBatch = storeAfterRestart.freezeNextBatch(maxSize: 20, newBatchId: {
            mintedFreshBatchId = true
            return "should-never-be-used"
        })
        #expect(!mintedFreshBatchId)
        #expect(afterRestartBatch?.batchId == batchId)

        #expect(storeAfterRestart.loadAll().map(\.eventId).contains("e4"))

        storeAfterRestart.markSent(batchId: batchId)
        #expect(storeAfterRestart.currentBatch() == nil)
        #expect(storeAfterRestart.loadAll().map(\.eventId) == ["e4"])
    }

    @Test func survivesSimulatedProcessDeath_pendingEventsWithNoFrozenBatchAlsoSurvive() throws {
        let url = tempDatabaseURL()
        do {
            let storeBeforeCrash = try SQLiteGeofenceEventQueueStore(url: url)
            storeBeforeCrash.enqueue(makeEvent("e1"))
            storeBeforeCrash.enqueue(makeEvent("e2"))
        }
        let storeAfterRestart = try SQLiteGeofenceEventQueueStore(url: url)

        #expect(storeAfterRestart.currentBatch() == nil)
        #expect(storeAfterRestart.loadAll().map(\.eventId) == ["e1", "e2"])
    }

    // MARK: - Rollback path (mirrors SQLiteFixStoreTests's post-review addition)

    @Test func withTransaction_bodyWritesThenThrows_rollsBackTheWrite() throws {
        struct InjectedFailure: Error {}
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))

        #expect(throws: InjectedFailure.self) {
            try store.withTransaction {
                try store.exec("DELETE FROM geofence_events WHERE eventId = 'e1';")
                throw InjectedFailure()
            }
        }

        #expect(store.loadAll().map(\.eventId) == ["e1"], "the DELETE must have been rolled back, not committed")
    }

    @Test func withTransaction_bodySucceeds_commitsNormally() throws {
        let store = try SQLiteGeofenceEventQueueStore(url: tempDatabaseURL())
        store.enqueue(makeEvent("e1"))

        try store.withTransaction {
            try store.exec("DELETE FROM geofence_events WHERE eventId = 'e1';")
        }

        #expect(store.loadAll().isEmpty)
    }
}
