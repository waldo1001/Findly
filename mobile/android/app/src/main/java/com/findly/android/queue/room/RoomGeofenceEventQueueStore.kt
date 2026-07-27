package com.findly.android.queue.room

import com.findly.android.queue.GeofenceEventBatch
import com.findly.android.queue.GeofenceEventQueueStore
import com.findly.android.queue.QueuedGeofenceEvent
import java.util.UUID

/**
 * The durable, Room-backed [GeofenceEventQueueStore] (specs/009-device-runtime.md §6.3's "same
 * durability bar" as the fix queue, §2) — mirrors [RoomFixQueueStore]'s statelessness property
 * (every method derives its answer fresh from [dao], nothing survives only in memory) for the same
 * "survives process death" reason. Backed by the same [FindlyDatabase] as the fix queue (one Room
 * database, per A10's convention), not a second one.
 */
class RoomGeofenceEventQueueStore(
    private val dao: GeofenceEventDao,
    private val batchIdGenerator: () -> String = { UUID.randomUUID().toString() },
) : GeofenceEventQueueStore {

    override suspend fun enqueue(event: QueuedGeofenceEvent) {
        dao.insert(event.toEntity())
    }

    override suspend fun pendingCount(): Int = dao.pendingCount()

    override suspend fun nextBatch(maxSize: Int): GeofenceEventBatch? {
        val (batchId, entities) = dao.freezeNextBatch(maxSize) { batchIdGenerator() } ?: return null
        return GeofenceEventBatch(batchId, entities.map { it.toQueuedEvent() })
    }

    override suspend fun markBatchSent(batchId: String) {
        requireInFlight(batchId)
        dao.markSent(batchId)
    }

    override suspend fun markBatchFailedTransient(batchId: String) {
        requireInFlight(batchId, allowNoBatch = true)
        dao.failTransient(batchId)
    }

    override suspend fun clearAll() {
        dao.clearAll()
    }

    /** Mirrors [RoomFixQueueStore.requireInFlight] — a caller resolving a batch id that isn't the
     * currently frozen one is a programming error, not a legitimate race. */
    private suspend fun requireInFlight(batchId: String, allowNoBatch: Boolean = false) {
        val current = dao.currentBatchId()
        if (current == null && allowNoBatch) return
        require(current == batchId) { "batchId mismatch: expected $current, got $batchId" }
    }
}

private fun QueuedGeofenceEvent.toEntity(): GeofenceEventEntity = GeofenceEventEntity(
    eventId = eventId,
    geofenceId = geofenceId,
    transition = transition,
    recordedAt = recordedAt,
    batchId = null,
)

private fun GeofenceEventEntity.toQueuedEvent(): QueuedGeofenceEvent = QueuedGeofenceEvent(
    eventId = eventId,
    geofenceId = geofenceId,
    transition = transition,
    recordedAt = recordedAt,
)
