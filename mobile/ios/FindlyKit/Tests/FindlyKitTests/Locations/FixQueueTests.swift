import Testing
@testable import FindlyKit

/// specs/004-ios-client.md §6, specs/001 §5.1, specs/000 §D7 — freeze-on-first-send batching,
/// retry-same-batchId, accept clears, definitive rejection issues a new id, queue > 100 splits.
struct FixQueueTests {

    func makeFix(_ id: String) -> LocationFix {
        LocationFix(fixId: id, recordedAt: "2026-07-19T09:00:00Z", lat: 51.0, lon: 3.7, accuracyM: 10, batteryPct: 80, source: .periodic)
    }

    @Test func nextBatchToSend_freezesQueuedFixesWithAFreshBatchId() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix("f1"))
        await queue.enqueue(makeFix("f2"))

        let batch = await queue.nextBatchToSend()

        #expect(batch?.batchId == "batch-1")
        #expect(batch?.fixes.map(\.fixId) == ["f1", "f2"])
    }

    @Test func nextBatchToSend_calledAgainWithoutResolution_returnsTheSameFrozenBatch() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix("f1"))

        let first = await queue.nextBatchToSend()
        // A fix recorded AFTER freezing must not join the in-flight batch.
        await queue.enqueue(makeFix("f2"))
        let retry = await queue.nextBatchToSend()

        #expect(first == retry)
        #expect(retry?.fixes.map(\.fixId) == ["f1"])
    }

    @Test func handleAccepted_removesTheBatchsFixes_andAllowsTheNextOneThrough() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix("f1"))
        await queue.enqueue(makeFix("f2"))

        let first = await queue.nextBatchToSend()!
        await queue.handleAccepted(batchId: first.batchId)

        let remainingCount = await queue.queuedCount()
        #expect(remainingCount == 0)

        await queue.enqueue(makeFix("f3"))
        let next = await queue.nextBatchToSend()
        #expect(next?.batchId == "batch-2")
        #expect(next?.fixes.map(\.fixId) == ["f3"])
    }

    @Test func handleTransientFailure_keepsTheSameBatchIdAndContentForRetry() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix("f1"))

        let first = await queue.nextBatchToSend()!
        await queue.handleTransientFailure(batchId: first.batchId)
        let retried = await queue.nextBatchToSend()

        #expect(retried == first, "retries after a transport/5xx failure MUST resend identical content under the same batchId")
    }

    @Test func handleDefinitiveRejection_dropsTheDeadBatch_andIssuesANewIdForTheRemainder() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        await queue.enqueue(makeFix("bad-fix"))
        await queue.enqueue(makeFix("good-fix"))

        let first = await queue.nextBatchToSend()!
        // Definitive rejection: server wrote no marker, the batch is dead. Drop just the offending
        // fix; the remainder gets a NEW batchId, never the dead one.
        await queue.handleDefinitiveRejection(batchId: first.batchId, dropFixIds: ["bad-fix"])

        let next = await queue.nextBatchToSend()
        #expect(next?.batchId == "batch-2", "the remainder MUST NOT reuse the dead batchId")
        #expect(next?.fixes.map(\.fixId) == ["good-fix"])
    }

    @Test func queueLargerThanMaxBatchSize_splitsAcrossSequentialBatches() async {
        var counter = 0
        let queue = FixQueue(generateBatchId: { counter += 1; return "batch-\(counter)" })
        for i in 0..<150 {
            await queue.enqueue(makeFix("f\(i)"))
        }

        let first = await queue.nextBatchToSend(maxBatchSize: 100)!
        #expect(first.fixes.count == 100)
        await queue.handleAccepted(batchId: first.batchId)

        let second = await queue.nextBatchToSend(maxBatchSize: 100)!
        #expect(second.fixes.count == 50)
        #expect(second.batchId != first.batchId)
    }
}
