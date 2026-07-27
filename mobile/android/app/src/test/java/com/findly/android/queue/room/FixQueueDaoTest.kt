package com.findly.android.queue.room

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Exercises [FixQueueDao]'s `@Transaction` composite methods against [FakeFixQueueDao] — the
 * exact same code Room will run against real SQLite in production (see [FixQueueDao]'s doc).
 * This is where specs/009-device-runtime.md §2's durable-queue correctness properties are
 * actually verified: the atomic "batchId + frozen fix set together" guarantee, insertion-order
 * preservation, and the 1 000-cap oldest-first drop.
 */
class FixQueueDaoTest {

    private fun entity(id: String, batchId: String? = null) = FixEntity(
        fixId = id,
        recordedAt = "2026-07-19T09:00:00Z",
        lat = 51.0,
        lon = 3.7,
        accuracyM = 10.0,
        altitudeM = null,
        speedMps = null,
        bearingDeg = null,
        batteryPct = 80,
        source = "periodic",
        batchId = batchId,
    )

    @Test
    fun `freezeNextBatch returns null when nothing is pending`() = runTest {
        val dao = FakeFixQueueDao()

        assertNull(dao.freezeNextBatch(100) { "batch-x" })
    }

    @Test
    fun `freezeNextBatch persists batchId on the fix rows themselves - the atomic unit`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))

        val (batchId, fixes) = requireNotNull(dao.freezeNextBatch(100) { "batch-1" })

        assertEquals("batch-1", batchId)
        assertEquals(listOf("a", "b"), fixes.map { it.fixId })
        // The defining correctness property (specs/009 §2): batchId lives ON the persisted rows,
        // not in any separate in-memory field - a fresh read (simulating a post-crash restart,
        // §"process death") sees it without any object having "remembered" it.
        assertEquals(listOf("batch-1", "batch-1"), dao.snapshot().map { it.batchId })
    }

    @Test
    fun `a freshly constructed dao view over the same table sees the identical in-flight batch (simulated process death)`() = runTest {
        val backingRows = FakeFixQueueDao()
        backingRows.insert(entity("a"))
        backingRows.insert(entity("b"))
        val (originalBatchId, _) = requireNotNull(backingRows.freezeNextBatch(100) { "batch-1" })

        // Simulate "process restarted, a brand new RoomFixQueueStore/dao wrapper is constructed
        // over the same on-disk table" by re-deriving state fresh from the same persisted rows -
        // no field on the first dao instance is consulted below.
        val persistedRows = backingRows.snapshot()
        val rehydrated = FakeFixQueueDao()
        for (row in persistedRows) rehydrated.insert(row)

        val (recoveredBatchId, recoveredFixes) = requireNotNull(rehydrated.freezeNextBatch(100) { "should-not-be-used" })

        assertEquals("retry after crash must resend the identical batchId", originalBatchId, recoveredBatchId)
        assertEquals(listOf("a", "b"), recoveredFixes.map { it.fixId })
    }

    @Test
    fun `freezeNextBatch is idempotent - repeated calls before resolution return the same batchId and fixes`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))

        val first = dao.freezeNextBatch(100) { "batch-1" }
        val second = dao.freezeNextBatch(100) { "should-not-be-called" }

        assertEquals(first, second)
    }

    @Test
    fun `a fix enqueued while a batch is in-flight does not join it`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        val (batchId, firstFixes) = requireNotNull(dao.freezeNextBatch(100) { "batch-1" })
        dao.insert(entity("b"))

        val (stillBatchId, stillFixes) = requireNotNull(dao.freezeNextBatch(100) { "should-not-be-called" })

        assertEquals(batchId, stillBatchId)
        assertEquals(listOf("a"), firstFixes.map { it.fixId })
        assertEquals(listOf("a"), stillFixes.map { it.fixId })
        assertEquals(2, dao.pendingCount()) // "a" (frozen) + "b" (queued, excluded from the batch)
    }

    @Test
    fun `accept removes exactly the batch's fixes`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))
        val (batchId, _) = requireNotNull(dao.freezeNextBatch(100) { "batch-1" })

        dao.accept(batchId)

        assertEquals(0, dao.pendingCount())
        assertNull(dao.freezeNextBatch(100) { "unused" })
    }

    @Test
    fun `reject drops only named offenders and un-freezes the remainder for a fresh batchId`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))
        val (batchId, _) = requireNotNull(dao.freezeNextBatch(100) { "batch-1" })

        dao.reject(batchId, offendingFixIds = setOf("a"))

        assertEquals(1, dao.pendingCount())
        val (nextBatchId, nextFixes) = requireNotNull(dao.freezeNextBatch(100) { "batch-2" })
        assertEquals(listOf("b"), nextFixes.map { it.fixId })
        assertTrue("a fresh batchId is assigned", nextBatchId != batchId)
    }

    @Test
    fun `failTransient changes nothing - identical retry`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        val (batchId, original) = requireNotNull(dao.freezeNextBatch(100) { "batch-1" })

        dao.failTransient(batchId)

        val (retriedBatchId, retriedFixes) = requireNotNull(dao.freezeNextBatch(100) { "unused" })
        assertEquals(batchId, retriedBatchId)
        assertEquals(original, retriedFixes)
    }

    @Test
    fun `freezeNextBatch never exceeds maxSize, splitting a larger backlog across calls`() = runTest {
        val dao = FakeFixQueueDao()
        repeat(5) { dao.insert(entity("fix-$it")) }

        val (_, fixes) = requireNotNull(dao.freezeNextBatch(3) { "batch-1" })

        assertEquals(3, fixes.size)
        assertEquals(listOf("fix-0", "fix-1", "fix-2"), fixes.map { it.fixId })
    }

    @Test
    fun `insertion order is preserved regardless of which fix resolves first`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("c"))
        dao.insert(entity("a"))
        dao.insert(entity("b"))

        assertEquals(listOf("c", "a", "b"), dao.pendingFixesOrdered().map { it.fixId })
    }

    @Test
    fun `enqueueAndCap drops the oldest pending fixes first on overflow, never touching an in-flight batch`() = runTest {
        val dao = FakeFixQueueDao()
        repeat(3) { dao.insert(entity("frozen-$it")) }
        dao.freezeNextBatch(100) { "batch-1" } // "frozen-0..2" now in-flight, protected from the cap
        repeat(5) { dao.insert(entity("pending-$it")) }

        // Cap at 6 total (3 frozen + 3 pending survive; 2 oldest pending dropped).
        val dropped = dao.enqueueAndCap(entity("newest"), cap = 6)

        assertEquals(3, dropped) // pending-0, pending-1, pending-2 (oldest of the 6 pending) dropped
        assertEquals(6, dao.totalCount())
        assertEquals(
            listOf("frozen-0", "frozen-1", "frozen-2"),
            dao.fixesInBatch("batch-1").map { it.fixId },
        )
        assertEquals(
            listOf("pending-3", "pending-4", "newest"),
            dao.pendingFixesOrdered().map { it.fixId },
        )
    }

    @Test
    fun `enqueueAndCap is a no-op below the cap`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))

        val dropped = dao.enqueueAndCap(entity("b"), cap = 1000)

        assertEquals(0, dropped)
        assertEquals(2, dao.totalCount())
    }

    @Test
    fun `clearAll drops every pending and in-flight fix (specs 008 §4_4 local-state wipe)`() = runTest {
        val dao = FakeFixQueueDao()
        dao.insert(entity("a"))
        dao.insert(entity("b"))
        dao.freezeNextBatch(1) { "batch-1" }

        dao.clearAll()

        assertEquals(0, dao.pendingCount())
        assertNull(dao.freezeNextBatch(100) { "unused" })
    }
}
