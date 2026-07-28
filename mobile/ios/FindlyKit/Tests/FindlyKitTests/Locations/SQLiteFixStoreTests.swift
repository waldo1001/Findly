import Foundation
import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §2 — the durable, SQLite-backed `FixStoring`. The single most
/// important test in this file is `survivesSimulatedProcessDeath...`: it constructs a fresh
/// `SQLiteFixStore` pointed at the same on-disk file a previous instance froze a batch with,
/// proving the batch identity + exact fix set survive a process restart — the property I10 exists
/// for (see `FixStoring.swift`'s doc and this task's report for the full rationale).
struct SQLiteFixStoreTests {

    func makeFix(_ id: String, recordedAt: String = "2026-07-19T09:00:00Z") -> LocationFix {
        LocationFix(fixId: id, recordedAt: recordedAt, lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    func tempDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("findly-test-\(UUID().uuidString).sqlite")
    }

    // MARK: - Basic durability plumbing

    @Test func loadAll_isEmptyForAFreshDatabase() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        #expect(store.loadAll().isEmpty)
    }

    @Test func append_thenLoadAll_preservesInsertionOrder() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        store.append(makeFix("f3"))

        #expect(store.loadAll().map(\.fixId) == ["f1", "f2", "f3"])
    }

    @Test func remove_dropsOnlyTheNamedFixes() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        store.append(makeFix("f3"))

        store.remove(fixIds: ["f2"])

        #expect(store.loadAll().map(\.fixId) == ["f1", "f3"])
    }

    // MARK: - The 1 000-fix cap (specs/009 §2)

    @Test func append_overCap_dropsOldestPendingFirst_andReturnsTheDroppedCount() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL(), cap: 3)
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        store.append(makeFix("f3"))
        let dropped = store.append(makeFix("f4"))

        #expect(dropped == 1)
        #expect(store.loadAll().map(\.fixId) == ["f2", "f3", "f4"])
    }

    @Test func append_overCap_neverDropsAFrozenInFlightFix() throws {
        var counter = 0
        // cap=3 leaves room for the 2 frozen fixes plus exactly 1 surviving pending fix, so the
        // drop from the 4th append lands on the OLDEST PENDING row (f3), never on a frozen one.
        let store = try SQLiteFixStore(url: tempDatabaseURL(), cap: 3)
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        // Freeze f1/f2 as in-flight before the cap is ever exceeded.
        _ = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })

        store.append(makeFix("f3")) // total 3, at cap, no overflow yet
        let dropped = store.append(makeFix("f4")) // total 4, overflow 1 - f3 is the oldest pending

        #expect(dropped == 1)
        let all = store.loadAll()
        #expect(all.map(\.fixId).contains("f1"))
        #expect(all.map(\.fixId).contains("f2"))
        #expect(all.map(\.fixId).contains("f4"))
        #expect(!all.map(\.fixId).contains("f3"))
    }

    @Test func append_loggingCallback_receivesACountOnly() throws {
        var droppedCounts: [Int] = []
        let store = try SQLiteFixStore(url: tempDatabaseURL(), cap: 1, onOverflowDropped: { droppedCounts.append($0) })
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))

        #expect(droppedCounts == [1])
    }

    // MARK: - Freeze-on-first-ask (specs/001 §5.1 rule 1, specs/009 §2)

    @Test func freezeNextBatch_freezesPendingFixesUnderAFreshBatchId() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))

        let batch = store.freezeNextBatch(maxSize: 100, newBatchId: { "batch-1" })

        #expect(batch?.batchId == "batch-1")
        #expect(batch?.fixes.map(\.fixId) == ["f1", "f2"])
    }

    @Test func freezeNextBatch_calledAgain_returnsTheSameFrozenBatch_notANewOne() throws {
        var counter = 0
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        let first = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })
        store.append(makeFix("f2")) // recorded after freezing - must not join the in-flight batch

        let retry = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })

        #expect(first == retry)
        #expect(retry?.fixes.map(\.fixId) == ["f1"])
        #expect(counter == 1, "newBatchId must not be invoked on a retry")
    }

    @Test func freezeNextBatch_nothingPending_returnsNil() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        #expect(store.freezeNextBatch(maxSize: 100, newBatchId: { "batch-1" }) == nil)
    }

    @Test func currentBatch_reflectsTheFrozenBatchWithoutFreezingAgain() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        _ = store.freezeNextBatch(maxSize: 100, newBatchId: { "batch-1" })

        #expect(store.currentBatch()?.batchId == "batch-1")
        #expect(store.currentBatch()?.fixes.map(\.fixId) == ["f1"])
    }

    @Test func markAccepted_removesExactlyThatBatchsFixes() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        let batch = store.freezeNextBatch(maxSize: 1, newBatchId: { "batch-1" })!
        // f2 is still pending (batch size 1) - accept must not touch it.
        store.markAccepted(batchId: batch.batchId)

        #expect(store.currentBatch() == nil)
        #expect(store.loadAll().map(\.fixId) == ["f2"])
    }

    @Test func markRejected_dropsOnlyTheNamedFixes_andUnfreezesTheRemainder() throws {
        var counter = 0
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("bad-fix"))
        store.append(makeFix("good-fix"))
        let batch = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })!

        store.markRejected(batchId: batch.batchId, dropFixIds: ["bad-fix"])

        #expect(store.currentBatch() == nil, "the remainder must be un-frozen, not left dangling under the dead batchId")
        #expect(store.loadAll().map(\.fixId) == ["good-fix"])

        let next = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })
        #expect(next?.batchId == "batch-2", "the remainder must get a NEW batchId, never the dead one")
    }

    @Test func markRejected_nilDropFixIds_dropsTheWholeBatch() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        let batch = store.freezeNextBatch(maxSize: 100, newBatchId: { "batch-1" })!

        store.markRejected(batchId: batch.batchId, dropFixIds: nil)

        #expect(store.loadAll().isEmpty)
        #expect(store.currentBatch() == nil)
    }

    @Test func removeAll_wipesPendingAndFrozenFixesAlike() throws {
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        _ = store.freezeNextBatch(maxSize: 1, newBatchId: { "batch-1" })

        store.removeAll()

        #expect(store.loadAll().isEmpty)
        #expect(store.currentBatch() == nil)
    }

    // MARK: - The central correctness property (specs/009 §2): survives simulated process death

    @Test func survivesSimulatedProcessDeath_inFlightBatchIdentityAndFixSetAreIntactAfterReopening() throws {
        let url = tempDatabaseURL()
        let batchId: String
        let frozenFixIds: [String]
        do {
            // "Process A": freeze a batch, then vanish WITHOUT ever resolving it (no accept/
            // reject/transient-failure call) - simulating a crash between POST /locations being
            // sent and its response being processed.
            let storeBeforeCrash = try SQLiteFixStore(url: url)
            storeBeforeCrash.append(makeFix("f1"))
            storeBeforeCrash.append(makeFix("f2"))
            storeBeforeCrash.append(makeFix("f3"))
            let frozen = storeBeforeCrash.freezeNextBatch(maxSize: 100, newBatchId: { "batch-before-crash" })!
            batchId = frozen.batchId
            frozenFixIds = frozen.fixes.map(\.fixId)
            // A fix recorded after the freeze - must also survive, as a still-pending row.
            storeBeforeCrash.append(makeFix("f4"))
        }
        // storeBeforeCrash's SQLite connection is now closed/deallocated - the SQLite equivalent
        // of the process dying. "Process B": a FRESH SQLiteFixStore instance pointed at the exact
        // same file, constructed as if from a cold app launch.
        let storeAfterRestart = try SQLiteFixStore(url: url)

        let recovered = storeAfterRestart.currentBatch()
        #expect(recovered?.batchId == batchId, "the in-flight batchId must survive process death unchanged")
        #expect(recovered?.fixes.map(\.fixId) == frozenFixIds, "the exact frozen fix set must survive, in the same order")

        // The store must not mint a NEW batch for the still-frozen fixes - freezeNextBatch after
        // restart must return the SAME batch, not a fresh one from a naive "next 100 pending"
        // recomputation (which would defeat batch-level idempotency, specs/009 §2's whole point).
        var mintedFreshBatchId = false
        let afterRestartBatch = storeAfterRestart.freezeNextBatch(maxSize: 100, newBatchId: {
            mintedFreshBatchId = true
            return "should-never-be-used"
        })
        #expect(!mintedFreshBatchId)
        #expect(afterRestartBatch?.batchId == batchId)

        // f4 (queued after the freeze, before the "crash") must also have survived, as pending.
        #expect(storeAfterRestart.loadAll().map(\.fixId).contains("f4"))

        // Resolving the recovered batch (as if the retried POST finally got a 2xx) must behave
        // exactly like any other accept: the frozen fixes go away, f4 remains queued.
        storeAfterRestart.markAccepted(batchId: batchId)
        #expect(storeAfterRestart.currentBatch() == nil)
        #expect(storeAfterRestart.loadAll().map(\.fixId) == ["f4"])
    }

    @Test func survivesSimulatedProcessDeath_pendingFixesWithNoFrozenBatchAlsoSurvive() throws {
        let url = tempDatabaseURL()
        do {
            let storeBeforeCrash = try SQLiteFixStore(url: url)
            storeBeforeCrash.append(makeFix("f1"))
            storeBeforeCrash.append(makeFix("f2"))
            // Never frozen - a crash before the next flush cycle ever ran.
        }
        let storeAfterRestart = try SQLiteFixStore(url: url)

        #expect(storeAfterRestart.currentBatch() == nil)
        #expect(storeAfterRestart.loadAll().map(\.fixId) == ["f1", "f2"])
    }

    // MARK: - Minor finding (post-review): the ROLLBACK path must actually be exercised

    /// `withTransaction`'s `catch { ROLLBACK }` existed but nothing forced a mid-transaction
    /// failure to prove pre-failure state survives untouched — a single-statement failure (e.g.
    /// `append`'s `insert` hitting the `fixId UNIQUE` constraint) doesn't prove this on its own,
    /// since nothing had been written yet for ROLLBACK to undo. This directly drives the internal
    /// (not private, `@testable`-visible — see `withTransaction`'s doc) transaction helper with a
    /// body that performs a REAL write via a second statement and then throws, proving SQLite's
    /// ROLLBACK actually undoes it rather than merely relying on Swift-level early-exit control
    /// flow having never written anything in the first place.
    @Test func withTransaction_bodyWritesThenThrows_rollsBackTheWrite() throws {
        struct InjectedFailure: Error {}
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))

        #expect(throws: InjectedFailure.self) {
            try store.withTransaction {
                // A real write, executed and (absent a rollback) durably applied by this point.
                try store.exec("DELETE FROM fixes WHERE fixId = 'f1';")
                throw InjectedFailure()
            }
        }

        #expect(store.loadAll().map(\.fixId) == ["f1"], "the DELETE must have been rolled back, not committed")
    }

    @Test func withTransaction_bodySucceeds_commitsNormally() throws {
        // The commit-path counterpart, so the rollback test above isn't the only thing exercising
        // this helper directly.
        let store = try SQLiteFixStore(url: tempDatabaseURL())
        store.append(makeFix("f1"))

        try store.withTransaction {
            try store.exec("DELETE FROM fixes WHERE fixId = 'f1';")
        }

        #expect(store.loadAll().isEmpty)
    }
}
