import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §2 — `InMemoryFixStore` reimplements the widened `FixStoring`
/// protocol (I10); these tests cover the cap/overflow behavior that `FixQueueTests.swift` (which
/// only exercises `FixQueue`'s pass-through API) never touches, so both `FixStoring`
/// implementations (this one and `SQLiteFixStore`) are verified against equivalent cases.
struct InMemoryFixStoreTests {

    func makeFix(_ id: String) -> LocationFix {
        LocationFix(fixId: id, recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    @Test func append_overCap_dropsOldestPendingFirst_andReturnsTheDroppedCount() {
        let store = InMemoryFixStore(cap: 3)
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        store.append(makeFix("f3"))
        let dropped = store.append(makeFix("f4"))

        #expect(dropped == 1)
        #expect(store.loadAll().map(\.fixId) == ["f2", "f3", "f4"])
    }

    @Test func append_overCap_neverDropsAFrozenInFlightFix() {
        var counter = 0
        let store = InMemoryFixStore(cap: 3)
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))
        _ = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })

        store.append(makeFix("f3"))
        let dropped = store.append(makeFix("f4"))

        #expect(dropped == 1)
        let all = store.loadAll().map(\.fixId)
        #expect(all.contains("f1"))
        #expect(all.contains("f2"))
        #expect(all.contains("f4"))
        #expect(!all.contains("f3"))
    }

    @Test func append_loggingCallback_receivesACountOnly() {
        var droppedCounts: [Int] = []
        let store = InMemoryFixStore(cap: 1, onOverflowDropped: { droppedCounts.append($0) })
        store.append(makeFix("f1"))
        store.append(makeFix("f2"))

        #expect(droppedCounts == [1])
    }

    @Test func markRejected_unfreezesTheRemainder_forANewBatchIdNextTime() {
        var counter = 0
        let store = InMemoryFixStore()
        store.append(makeFix("bad-fix"))
        store.append(makeFix("good-fix"))
        let batch = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })!

        store.markRejected(batchId: batch.batchId, dropFixIds: ["bad-fix"])

        #expect(store.currentBatch() == nil)
        #expect(store.loadAll().map(\.fixId) == ["good-fix"])

        let next = store.freezeNextBatch(maxSize: 100, newBatchId: { counter += 1; return "batch-\(counter)" })
        #expect(next?.batchId == "batch-2")
    }
}
