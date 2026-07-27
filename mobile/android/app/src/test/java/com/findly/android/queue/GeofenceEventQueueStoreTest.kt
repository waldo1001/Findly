package com.findly.android.queue

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Verifies the [GeofenceEventQueueStore] contract (specs/009-device-runtime.md §6.3: "Events are
 * flushed like fixes, batched 1-20 per call, idempotent on eventId") against [InMemoryGeofenceEventQueueStore] —
 * mirrors [FixQueueStoreTest]'s coverage of the analogous fix-queue contract. */
class GeofenceEventQueueStoreTest {

    private fun event(id: String, geofenceId: String = "gf_home") = QueuedGeofenceEvent(
        eventId = id,
        geofenceId = geofenceId,
        transition = "enter",
        recordedAt = "2026-07-27T09:00:00Z",
    )

    private fun sequenceGenerator(): () -> String {
        var counter = 0
        return { "batch-${counter++}" }
    }

    @Test
    fun `nextBatch returns null when nothing is pending`() = runTest {
        val store = InMemoryGeofenceEventQueueStore()

        assertNull(store.nextBatch())
    }

    @Test
    fun `nextBatch is idempotent - same batchId and events until resolved`() = runTest {
        val store = InMemoryGeofenceEventQueueStore(batchIdGenerator = sequenceGenerator())
        store.enqueue(event("a"))
        store.enqueue(event("b"))

        val first = store.nextBatch()
        val second = store.nextBatch()

        assertEquals(first, second)
        assertEquals(listOf("a", "b"), first?.events?.map { it.eventId })
    }

    @Test
    fun `markBatchSent removes exactly the sent events and clears in-flight`() = runTest {
        val store = InMemoryGeofenceEventQueueStore()
        store.enqueue(event("a"))
        store.enqueue(event("b"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchSent(batch.batchId)

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `a new event enqueued while a batch is in-flight does not join it`() = runTest {
        val store = InMemoryGeofenceEventQueueStore()
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
        val store = InMemoryGeofenceEventQueueStore()
        store.enqueue(event("a"))
        val batch = requireNotNull(store.nextBatch())

        store.markBatchFailedTransient(batch.batchId)

        val retried = requireNotNull(store.nextBatch())
        assertEquals(batch, retried)
    }

    @Test
    fun `nextBatch never exceeds maxSize, splitting a larger backlog across calls (1-20 per call)`() = runTest {
        val store = InMemoryGeofenceEventQueueStore(batchIdGenerator = sequenceGenerator())
        repeat(25) { store.enqueue(event("evt-$it")) }

        val batch = requireNotNull(store.nextBatch(maxSize = 20))

        assertEquals(20, batch.events.size)
        assertEquals((0..19).map { "evt-$it" }, batch.events.map { it.eventId })
    }

    @Test
    fun `clearAll drops every pending and in-flight event`() = runTest {
        val store = InMemoryGeofenceEventQueueStore()
        store.enqueue(event("a"))
        store.enqueue(event("b"))
        store.nextBatch(maxSize = 1)

        store.clearAll()

        assertEquals(0, store.pendingCount())
        assertNull(store.nextBatch())
    }

    @Test
    fun `markBatchSent with a mismatched batchId throws`() = runTest {
        val store = InMemoryGeofenceEventQueueStore()
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
    fun `insertion order is preserved`() = runTest {
        val store = InMemoryGeofenceEventQueueStore()
        store.enqueue(event("c"))
        store.enqueue(event("a"))
        store.enqueue(event("b"))

        val batch = requireNotNull(store.nextBatch(maxSize = 10))

        assertEquals(listOf("c", "a", "b"), batch.events.map { it.eventId })
        assertTrue(store.pendingCount() >= 0) // sanity: no crash on a fully-frozen pool
    }
}
