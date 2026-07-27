package com.findly.android.queue.room

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction

/**
 * Room DAO for the durable geofence-event queue (specs/009-device-runtime.md §6.3) — the same
 * "abstract primitives + real-bodied `@Transaction` composites" split as [FixQueueDao] (see its
 * doc for the full testability rationale). Simpler than [FixQueueDao]: no overflow cap (not
 * specified for events, unlike the fix queue's explicit 1 000 cap, §2) and no `reject` method
 * (001-api-contract.md §7.3 defines no per-event rejection shape — every non-`TRACKING_PAUSED`
 * failure just retries the same frozen batch, [GeofenceEventSyncCoordinator]'s job).
 */
@Dao
interface GeofenceEventDao {

    @Insert
    suspend fun insert(entity: GeofenceEventEntity)

    @Query("SELECT batchId FROM geofence_events WHERE batchId IS NOT NULL LIMIT 1")
    suspend fun currentBatchId(): String?

    @Query("SELECT * FROM geofence_events WHERE batchId IS NULL ORDER BY seq ASC")
    suspend fun pendingEventsOrdered(): List<GeofenceEventEntity>

    @Query("SELECT * FROM geofence_events WHERE batchId = :batchId ORDER BY seq ASC")
    suspend fun eventsInBatch(batchId: String): List<GeofenceEventEntity>

    @Query("UPDATE geofence_events SET batchId = :batchId WHERE eventId IN (:eventIds)")
    suspend fun assignBatch(batchId: String, eventIds: List<String>)

    @Query("DELETE FROM geofence_events WHERE eventId IN (:eventIds)")
    suspend fun deleteByIds(eventIds: List<String>)

    @Query("DELETE FROM geofence_events")
    suspend fun deleteAll()

    @Query("SELECT COUNT(*) FROM geofence_events")
    suspend fun totalCount(): Int

    // ---- composite, transactional queue logic (mirrors FixQueueDao) ----

    /** Freeze-on-first-ask: if a batch is already frozen, returns its identical id + event set
     * unchanged. Otherwise freezes the oldest ≤[maxSize] pending events under a fresh id from
     * [newBatchId]. `null` when nothing is pending. */
    @Transaction
    suspend fun freezeNextBatch(maxSize: Int, newBatchId: suspend () -> String): Pair<String, List<GeofenceEventEntity>>? {
        val existing = currentBatchId()
        if (existing != null) {
            return existing to eventsInBatch(existing)
        }
        val pending = pendingEventsOrdered()
        if (pending.isEmpty()) return null
        val slice = pending.take(maxSize)
        val batchId = newBatchId()
        assignBatch(batchId, slice.map { it.eventId })
        return batchId to slice.map { it.copy(batchId = batchId) }
    }

    /** Any 2xx response — removes exactly the batch's events, permanently. A no-op if [batchId]
     * doesn't match anything currently frozen (defensive; the store layer already guards against
     * a stale/mismatched caller). */
    @Transaction
    suspend fun markSent(batchId: String) {
        val events = eventsInBatch(batchId)
        if (events.isEmpty()) return
        deleteByIds(events.map { it.eventId })
    }

    /** Network error / 5xx / any other non-`TRACKING_PAUSED` failure — no-op on the pending pool;
     * the batch stays frozen under the same id for an identical retry. Kept as an explicit method
     * for the same reason as [FixQueueDao.failTransient]: the "changes nothing" contract gets one
     * obvious, named home. */
    @Suppress("UNUSED_PARAMETER")
    suspend fun failTransient(batchId: String) {
        // Intentionally empty.
    }

    /** Total events in the store, pending and frozen-in-flight alike. */
    suspend fun pendingCount(): Int = totalCount()

    /** Drops every row unconditionally (specs/008-privacy-endpoints.md §4.4 local-state wipe). */
    suspend fun clearAll() = deleteAll()
}
