import Testing
@testable import FindlyKit

/// specs/009-device-runtime.md §6.3 — freeze-on-first-send batching, retry-same-batchId,
/// sent-clears, 1-20 batching. Mirrors `FixQueueTests`'s coverage shape.
struct GeofenceEventQueueTests {

    func makeEvent(_ id: String) -> GeofenceEventReport {
        GeofenceEventReport(eventId: id, geofenceId: "gf_home", transition: .enter, recordedAt: "2026-07-19T09:00:00Z")
    }

    @Test func nextBatchToSend_freezesQueuedEventsWithAFreshBatchId() async {
        var counter = 0
        let queue = GeofenceEventQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeEvent("e1"))
        await queue.enqueue(makeEvent("e2"))

        let batch = await queue.nextBatchToSend()

        #expect(batch?.batchId == "batch-1")
        #expect(batch?.events.map(\.eventId) == ["e1", "e2"])
    }

    @Test func nextBatchToSend_calledAgainWithoutResolution_returnsTheSameFrozenBatch() async {
        var counter = 0
        let queue = GeofenceEventQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeEvent("e1"))

        let first = await queue.nextBatchToSend()
        await queue.enqueue(makeEvent("e2"))
        let retry = await queue.nextBatchToSend()

        #expect(first == retry)
        #expect(retry?.events.map(\.eventId) == ["e1"])
    }

    @Test func handleSent_removesTheBatchsEvents_andAllowsTheNextOneThrough() async {
        var counter = 0
        let queue = GeofenceEventQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeEvent("e1"))

        let first = await queue.nextBatchToSend()!
        await queue.handleSent(batchId: first.batchId)

        #expect(await queue.pendingCount() == 0)

        await queue.enqueue(makeEvent("e2"))
        let next = await queue.nextBatchToSend()
        #expect(next?.batchId == "batch-2")
    }

    @Test func handleTransientFailure_keepsTheSameBatchIdAndContentForRetry() async {
        var counter = 0
        let queue = GeofenceEventQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeEvent("e1"))

        let first = await queue.nextBatchToSend()!
        await queue.handleTransientFailure(batchId: first.batchId)
        let retried = await queue.nextBatchToSend()

        #expect(retried == first)
    }

    @Test func clearAll_removesQueuedEventsAndTheInFlightBatch() async {
        var counter = 0
        let queue = GeofenceEventQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeEvent("e1"))
        _ = await queue.nextBatchToSend()
        await queue.enqueue(makeEvent("e2"))

        await queue.clearAll()

        #expect(await queue.pendingCount() == 0)
        await queue.enqueue(makeEvent("e3"))
        let next = await queue.nextBatchToSend()
        #expect(next?.batchId == "batch-2")
        #expect(next?.events.map(\.eventId) == ["e3"])
    }

    @Test func queueLargerThanMaxBatchSize_splitsAcrossSequentialBatches() async {
        var counter = 0
        let queue = GeofenceEventQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        for i in 0..<25 {
            await queue.enqueue(makeEvent("e\(i)"))
        }

        let first = await queue.nextBatchToSend(maxBatchSize: 20)!
        #expect(first.events.count == 20)
        await queue.handleSent(batchId: first.batchId)

        let second = await queue.nextBatchToSend(maxBatchSize: 20)!
        #expect(second.events.count == 5)
        #expect(second.batchId != first.batchId)
    }
}
