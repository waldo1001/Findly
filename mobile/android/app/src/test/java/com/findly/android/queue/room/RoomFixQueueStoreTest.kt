package com.findly.android.queue.room

import com.findly.android.queue.FixSource
import com.findly.android.queue.QueuedFix
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * [RoomFixQueueStore] against [FakeFixQueueDao] — verifies the [com.findly.android.queue.FixQueueStore]
 * contract end to end (specs/003-android-client.md §10.2) through the Room-backed implementation,
 * plus the overflow-log-count-only wiring (specs/009-device-runtime.md §2) and the statelessness
 * property that makes "survives process death" true (see [RoomFixQueueStore]'s doc).
 */
class RoomFixQueueStoreTest {

    private fun fix(id: String) = QueuedFix(
        fixId = id,
        recordedAt = "2026-07-19T09:00:00Z",
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
        val store = RoomFixQueueStore(FakeFixQueueDao())

        assertNull(store.nextBatch())
    }

    @Test
    fun `nextBatch is idempotent - same batchId and fixes until resolved`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao(), batchIdGenerator = sequenceGenerator())
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))

        val first = store.nextBatch()
        val second = store.nextBatch()

        assertEquals(first, second)
        assertEquals(listOf("a", "b"), first?.fixes?.map { it.fixId })
    }

    @Test
    fun `markBatchAccepted removes exactly the acked fixes and clears in-flight`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao())
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchAccepted(batch.batchId)

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `a new fix enqueued while a batch is in-flight does not join it`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao())
        store.enqueue(fix("a"))
        val batch = requireNotNull(store.nextBatch())

        store.enqueue(fix("b"))

        val stillFrozen = requireNotNull(store.nextBatch())
        assertEquals(batch, stillFrozen)
        assertEquals(listOf("a"), stillFrozen.fixes.map { it.fixId })
        assertEquals(2, store.pendingCount())
    }

    @Test
    fun `markBatchRejected drops only named offenders and the remainder gets a fresh batchId next time`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao(), batchIdGenerator = sequenceGenerator())
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
        val store = RoomFixQueueStore(FakeFixQueueDao())
        store.enqueue(fix("a"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchFailedTransient(batch.batchId)

        val retried = requireNotNull(store.nextBatch())
        assertEquals(batch, retried)
    }

    @Test
    fun `nextBatch never exceeds maxSize, splitting a larger backlog across calls`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao(), batchIdGenerator = sequenceGenerator())
        repeat(5) { store.enqueue(fix("fix-$it")) }

        val batch = requireNotNull(store.nextBatch(maxSize = 3))

        assertEquals(3, batch.fixes.size)
        assertEquals(listOf("fix-0", "fix-1", "fix-2"), batch.fixes.map { it.fixId })
    }

    @Test
    fun `clearAll drops every pending and in-flight fix`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao())
        store.enqueue(fix("a"))
        store.enqueue(fix("b"))
        store.nextBatch(maxSize = 1)

        store.clearAll()

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `markBatchAccepted with a mismatched batchId throws`() = runTest {
        val store = RoomFixQueueStore(FakeFixQueueDao())
        store.enqueue(fix("a"))
        store.nextBatch()

        try {
            store.markBatchAccepted("not-the-real-batch-id")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `overflow past the 1000-fix cap drops the oldest and reports a count only, never coordinates or fixIds`() = runTest {
        val reportedCounts = mutableListOf<Int>()
        val store = RoomFixQueueStore(FakeFixQueueDao(), cap = 3, onOverflowDropped = { reportedCounts.add(it) })

        repeat(5) { store.enqueue(fix("fix-$it")) }

        assertEquals(listOf(1, 1), reportedCounts) // one drop event per enqueue that overflows
        assertEquals(3, store.pendingCount())
        val remaining = requireNotNull(store.nextBatch(maxSize = 10))
        assertEquals(listOf("fix-2", "fix-3", "fix-4"), remaining.fixes.map { it.fixId })
    }

    @Test
    fun `a fresh store instance over the same underlying dao recovers the identical in-flight batch (simulated process death)`() = runTest {
        val dao = FakeFixQueueDao()
        val beforeCrash = RoomFixQueueStore(dao, batchIdGenerator = sequenceGenerator())
        beforeCrash.enqueue(fix("a"))
        beforeCrash.enqueue(fix("b"))
        val frozenBeforeCrash = requireNotNull(beforeCrash.nextBatch())

        // A brand new RoomFixQueueStore (as happens after FindlyApplication.onCreate on a fresh
        // process) wrapping the SAME persisted dao - no state is carried over via any field.
        val afterRestart = RoomFixQueueStore(dao, batchIdGenerator = { "must-not-be-used" })

        val recovered = requireNotNull(afterRestart.nextBatch())
        assertEquals(frozenBeforeCrash, recovered)
    }
}
