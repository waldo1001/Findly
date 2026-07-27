package com.findly.android.queue.room

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** [GeofenceEventDao]'s composite `@Transaction` logic against [FakeGeofenceEventDao] — mirrors
 * `FixQueueDaoTest`'s coverage of the analogous fix-queue DAO. */
class GeofenceEventDaoTest {

    private fun entity(id: String, seq: Long = 0) = GeofenceEventEntity(
        seq = seq,
        eventId = id,
        geofenceId = "gf_home",
        transition = "enter",
        recordedAt = "2026-07-27T09:00:00Z",
        batchId = null,
    )

    private fun sequenceGenerator(): suspend () -> String {
        var counter = 0
        return { "batch-${counter++}" }
    }

    @Test
    fun `freezeNextBatch returns null when nothing is pending`() = runTest {
        val dao = FakeGeofenceEventDao()

        assertNull(dao.freezeNextBatch(20, sequenceGenerator()))
    }

    @Test
    fun `freezeNextBatch freezes the oldest pending events under a fresh batchId`() = runTest {
        val dao = FakeGeofenceEventDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))

        val (batchId, events) = requireNotNull(dao.freezeNextBatch(20, sequenceGenerator()))

        assertEquals("batch-0", batchId)
        assertEquals(listOf("a", "b"), events.map { it.eventId })
        assertTrue(events.all { it.batchId == batchId })
    }

    @Test
    fun `freezeNextBatch is idempotent while a batch is already in flight`() = runTest {
        val dao = FakeGeofenceEventDao()
        dao.insert(entity("a"))
        val first = requireNotNull(dao.freezeNextBatch(20, sequenceGenerator()))

        val second = dao.freezeNextBatch(20) { "must-not-be-used" }

        assertEquals(first, second)
    }

    @Test
    fun `freezeNextBatch never exceeds maxSize`() = runTest {
        val dao = FakeGeofenceEventDao()
        repeat(25) { dao.insert(entity("evt-$it", seq = it.toLong())) }

        val (_, events) = requireNotNull(dao.freezeNextBatch(20, sequenceGenerator()))

        assertEquals(20, events.size)
    }

    @Test
    fun `markSent removes exactly the batch's events`() = runTest {
        val dao = FakeGeofenceEventDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))
        val (batchId, _) = requireNotNull(dao.freezeNextBatch(20, sequenceGenerator()))

        dao.markSent(batchId)

        assertEquals(0, dao.totalCount())
    }

    @Test
    fun `markSent on an unknown batchId is a harmless no-op`() = runTest {
        val dao = FakeGeofenceEventDao()
        dao.insert(entity("a"))

        dao.markSent("no-such-batch")

        assertEquals(1, dao.totalCount())
    }

    @Test
    fun `pendingCount reflects total rows, pending and frozen alike`() = runTest {
        val dao = FakeGeofenceEventDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))
        dao.freezeNextBatch(1, sequenceGenerator())

        assertEquals(2, dao.pendingCount())
    }

    @Test
    fun `clearAll drops every row`() = runTest {
        val dao = FakeGeofenceEventDao()
        dao.insert(entity("a"))
        dao.freezeNextBatch(20, sequenceGenerator())
        dao.insert(entity("b"))

        dao.clearAll()

        assertEquals(0, dao.totalCount())
    }
}
