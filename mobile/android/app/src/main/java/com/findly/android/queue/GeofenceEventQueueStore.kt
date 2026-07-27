package com.findly.android.queue

/**
 * The durable geofence-event queue contract (specs/009-device-runtime.md §6.3: "Events are
 * flushed like fixes, batched 1-20 per call, idempotent on eventId") — deliberately mirrors
 * [FixQueueStore]'s freeze-on-first-ask shape (specs/003-android-client.md §10.2) so a transient
 * flush failure retries the exact same batch, even though the wire idempotency key here is
 * per-event (`eventId`, 001-api-contract.md §7.3) rather than per-batch like `POST /locations`'
 * `batchId` — there is no server-defined per-event rejection shape to react to, so unlike
 * [FixQueueStore] this contract has no `markBatchRejected`: every non-paused failure just retries.
 * [RoomGeofenceEventQueueStore][com.findly.android.queue.room.RoomGeofenceEventQueueStore] is the
 * durable, Room-backed production implementation (same [com.findly.android.queue.room.FindlyDatabase],
 * A10's pattern).
 */
interface GeofenceEventQueueStore {
    suspend fun enqueue(event: QueuedGeofenceEvent)
    suspend fun pendingCount(): Int

    /** Freezes (or returns the already-frozen) oldest ≤[maxSize] pending events under a stable
     * local batch id — repeated calls before the batch is resolved return the identical id + event
     * set. `null` when nothing is pending. [maxSize] defaults to 20 (001 §7.3's per-call cap). */
    suspend fun nextBatch(maxSize: Int = 20): GeofenceEventBatch?

    /** Any 2xx response, regardless of the `accepted`/`duplicates` split (idempotent on `eventId`
     * server-side, so a partially-duplicate batch is still fully resolved from the queue's point
     * of view). */
    suspend fun markBatchSent(batchId: String)

    /** Network error / 5xx / any other non-`TRACKING_PAUSED` failure — the batch stays frozen for
     * an identical retry (no per-event rejection shape is defined for this endpoint, so there is
     * nothing to drop). */
    suspend fun markBatchFailedTransient(batchId: String)

    /** Drops every pending/in-flight event unconditionally — used only by a full local-state wipe
     * after account deletion (specs/008-privacy-endpoints.md §4.4), same as [FixQueueStore.clearAll]. */
    suspend fun clearAll()
}
