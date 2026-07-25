package com.findly.android.queue

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Verifies the 001-api-contract.md §5.1 `batchId` idempotency rules encoded in
 * specs/003-android-client.md §10.2. */
class FixQueueStoreTest {

    private fun fix(id: String, recordedAt: String = "2026-07-19T09:00:00Z") = QueuedFix(
        fixId = id,
        recordedAt = recordedAt,
        lat = 51.0,
        lon = 3.7,
        accuracyM = 10.0,
        batteryPct = 80,
        source = FixSource.Periodic,
    )

    private fun sequenceGenerator(): () -> String {
        var counter = 0
        return { "batch-${counter++}" }
    }

    @Test
    fun `nextBatch returns null when nothing is pending`() = runTest {
        val store = InMemoryFixQueueStore()

        assertNull(store.nextBatch())
    }

    @Test
    fun `nextBatch is idempotent - same batchId and fixes until resolved`() = runTest {
        val store = InMemoryFixQueueStore(batchIdGenerator = sequenceGenerator())
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))

        val first = store.nextBatch()
        val second = store.nextBatch()

        assertEquals(first, second)
        assertEquals(listOf("a", "b"), first?.fixes?.map { it.fixId })
    }

    @Test
    fun `markBatchAccepted removes exactly the acked fixes and clears in-flight`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchAccepted(batch.batchId)

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `a new fix enqueued while a batch is in-flight does not join it`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        val batch = requireNotNull(store.nextBatch())

        store.enqueue(fix("b"))

        val stillFrozen = requireNotNull(store.nextBatch())
        assertEquals(batch, stillFrozen)
        assertEquals(listOf("a"), stillFrozen.fixes.map { it.fixId })
        assertEquals(2, store.pendingCount()) // "a" (frozen) + "b" (queued, excluded from the batch)
    }

    @Test
    fun `markBatchRejected drops only named offenders and the remainder gets a fresh batchId next time`() = runTest {
        val store = InMemoryFixQueueStore(batchIdGenerator = sequenceGenerator())
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchRejected(batch.batchId, offendingFixIds = setOf("a"))

        assertEquals(1, store.pendingCount())
        val nextBatch = requireNotNull(store.nextBatch())
        assertEquals(listOf("b"), nextBatch.fixes.map { it.fixId })
        assertTrue("a fresh batchId is assigned", nextBatch.batchId != batch.batchId)
    }

    @Test
    fun `markBatchFailedTransient changes nothing - identical retry`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchFailedTransient(batch.batchId)

        val retried = requireNotNull(store.nextBatch())
        assertEquals(batch, retried)
    }

    @Test
    fun `nextBatch never exceeds maxSize, splitting a larger backlog across calls`() = runTest {
        val store = InMemoryFixQueueStore(batchIdGenerator = sequenceGenerator())
        repeat(5) { store.enqueue(fix("fix-$it")) }

        val batch = requireNotNull(store.nextBatch(maxSize = 3))

        assertEquals(3, batch.fixes.size)
        assertEquals(listOf("fix-0", "fix-1", "fix-2"), batch.fixes.map { it.fixId })
    }

    @Test
    fun `markBatchAccepted with a mismatched batchId throws`() = runTest {
        val store = InMemoryFixQueueStore()
        store.enqueue(fix("a"))
        store.nextBatch()

        try {
            store.markBatchAccepted("not-the-real-batch-id")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }
}
