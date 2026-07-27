package com.findly.android.queue.room

import com.findly.android.queue.QueuedGeofenceEvent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

/** [RoomGeofenceEventQueueStore] against [FakeGeofenceEventDao] — mirrors [RoomFixQueueStoreTest]'s
 * coverage of the analogous fix-queue store, including the process-death recovery property. */
class RoomGeofenceEventQueueStoreTest {

    private fun event(id: String) = QueuedGeofenceEvent(
        eventId = id,
        geofenceId = "gf_home",
        transition = "enter",
        recordedAt = "2026-07-27T09:00:00Z",
    )

    private fun sequenceGenerator(): () -> String {
        var counter = 0
        return { "batch-${counter++}" }
    }

    @Test
    fun `nextBatch returns null when nothing is pending`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao())

        assertNull(store.nextBatch())
    }

    @Test
    fun `nextBatch is idempotent - same batchId and events until resolved`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao(), batchIdGenerator = sequenceGenerator())
        store.enqueue(event("a"))
        store.enqueue(event("b"))

        val first = store.nextBatch()
        val second = store.nextBatch()

        assertEquals(first, second)
        assertEquals(listOf("a", "b"), first?.events?.map { it.eventId })
    }

    @Test
    fun `markBatchSent removes exactly the sent events and clears in-flight`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao())
        store.enqueue(event("a"))
        store.enqueue(event("b"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchSent(batch.batchId)

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `a new event enqueued while a batch is in-flight does not join it`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao())
        store.enqueue(event("a"))
        val batch = requireNotNull(store.nextBatch())

        store.enqueue(event("b"))

        val stillFrozen = requireNotNull(store.nextBatch())
        assertEquals(batch, stillFrozen)
        assertEquals(listOf("a"), stillFrozen.events.map { it.eventId })
        assertEquals(2, store.pendingCount())
    }

    @Test
    fun `markBatchFailedTransient changes nothing - identical retry`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao())
        store.enqueue(event("a"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchFailedTransient(batch.batchId)

        val retried = requireNotNull(store.nextBatch())
        assertEquals(batch, retried)
    }

    @Test
    fun `nextBatch never exceeds maxSize, splitting a larger backlog across calls`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao(), batchIdGenerator = sequenceGenerator())
        repeat(25) { store.enqueue(event("evt-$it")) }

        val batch = requireNotNull(store.nextBatch(maxSize = 20))

        assertEquals(20, batch.events.size)
    }

    @Test
    fun `clearAll drops every pending and in-flight event`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao())
        store.enqueue(event("a"))
        store.enqueue(event("b"))
        store.nextBatch(maxSize = 1)

        store.clearAll()

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `markBatchSent with a mismatched batchId throws`() = runTest {
        val store = RoomGeofenceEventQueueStore(FakeGeofenceEventDao())
        store.enqueue(event("a"))
        store.nextBatch()

        try {
            store.markBatchSent("not-the-real-batch-id")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            // expected
        }
    }

    @Test
    fun `a fresh store instance over the same underlying dao recovers the identical in-flight batch (simulated process death)`() = runTest {
        val dao = FakeGeofenceEventDao()
        val beforeCrash = RoomGeofenceEventQueueStore(dao, batchIdGenerator = sequenceGenerator())
        beforeCrash.enqueue(event("a"))
        beforeCrash.enqueue(event("b"))
        val frozenBeforeCrash = requireNotNull(beforeCrash.nextBatch())

        val afterRestart = RoomGeofenceEventQueueStore(dao, batchIdGenerator = { "must-not-be-used" })

        val recovered = requireNotNull(afterRestart.nextBatch())
        assertEquals(frozenBeforeCrash, recovered)
    }
}
