package com.findly.android.queue

import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** A plain in-memory [GeofenceEventQueueStore] — used directly by higher-level composition tests
 * (e.g. `LocationSyncRunnerTest`-style harnesses) that don't need Room-level detail, mirroring
 * [InMemoryFixQueueStore]'s role for [FixQueueStore]. [com.findly.android.queue.room.RoomGeofenceEventQueueStore]
 * is the real, durable, production implementation (specs/009-device-runtime.md §6.3's "same
 * durability bar" as the fix queue, §2). */
class InMemoryGeofenceEventQueueStore(
    private val batchIdGenerator: () -> String = { UUID.randomUUID().toString() },
) : GeofenceEventQueueStore {

    private val mutex = Mutex()
    private val pending = mutableListOf<QueuedGeofenceEvent>()
    private var inFlight: GeofenceEventBatch? = null

    override suspend fun enqueue(event: QueuedGeofenceEvent) {
        mutex.withLock { pending.add(event) }
    }

    override suspend fun pendingCount(): Int = mutex.withLock { pending.size }

    override suspend fun nextBatch(maxSize: Int): GeofenceEventBatch? = mutex.withLock {
        inFlight?.let { return@withLock it }
        if (pending.isEmpty()) return@withLock null
        val slice = pending.take(maxSize)
        val batch = GeofenceEventBatch(batchIdGenerator(), slice)
        inFlight = batch
        batch
    }

    override suspend fun markBatchSent(batchId: String) {
        mutex.withLock {
            val batch = inFlight ?: return@withLock
            require(batch.batchId == batchId) {
                "batchId mismatch: expected ${batch.batchId}, got $batchId"
            }
            val sentIds = batch.events.map { it.eventId }.toSet()
            pending.removeAll { it.eventId in sentIds }
            inFlight = null
        }
    }

    override suspend fun markBatchFailedTransient(batchId: String) {
        mutex.withLock {
            val batch = inFlight
            if (batch != null) {
                require(batch.batchId == batchId) {
                    "batchId mismatch: expected ${batch.batchId}, got $batchId"
                }
            }
            // No-op on the pending pool: the batch stays frozen for an identical retry.
        }
    }

    override suspend fun clearAll() {
        mutex.withLock {
            pending.clear()
            inFlight = null
        }
    }
}
