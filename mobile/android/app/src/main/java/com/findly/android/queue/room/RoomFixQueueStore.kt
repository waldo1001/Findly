package com.findly.android.queue.room

import com.findly.android.queue.FixBatch
import com.findly.android.queue.FixQueueStore
import com.findly.android.queue.FixSource
import com.findly.android.queue.QueuedFix
import java.util.UUID

/**
 * The durable, Room-backed [FixQueueStore] (specs/009-device-runtime.md §2) that replaces the A1
 * in-memory placeholder (specs/003-android-client.md §10.4) behind the *unchanged* interface —
 * no call-site anywhere else in the app changes.
 *
 * Deliberately holds **no in-memory state of its own** (unlike
 * [com.findly.android.queue.InMemoryFixQueueStore]'s `pending`/`inFlight` fields) — every method
 * derives its answer fresh from [dao]. That statelessness is what "survives process death" means
 * in practice: a freshly-constructed instance after an app/process restart (as
 * `FindlyApplication.onCreate` does on every cold start) sees exactly the same in-flight batch a
 * pre-crash instance would have, because nothing about that batch's identity ever lived anywhere
 * but the `fixes` table itself (see [FixEntity]'s doc for why storing `batchId` on the row is the
 * load-bearing part of that guarantee).
 *
 * [onOverflowDropped] is invoked with a **count only** whenever the 1 000-fix cap drops fixes —
 * the real wiring (`AppContainer`) logs it at debug level; never coordinates, `deviceId`, or any
 * other identifying detail (docs/security-review-checklist.md).
 */
class RoomFixQueueStore(
    private val dao: FixQueueDao,
    private val batchIdGenerator: () -> String = { UUID.randomUUID().toString() },
    private val cap: Int = 1000,
    private val onOverflowDropped: (droppedCount: Int) -> Unit = {},
) : FixQueueStore {

    override suspend fun enqueue(fix: QueuedFix) {
        val dropped = dao.enqueueAndCap(fix.toEntity(), cap)
        if (dropped > 0) onOverflowDropped(dropped)
    }

    override suspend fun pendingCount(): Int = dao.pendingCount()

    override suspend fun nextBatch(maxSize: Int): FixBatch? {
        val (batchId, entities) = dao.freezeNextBatch(maxSize) { batchIdGenerator() } ?: return null
        return FixBatch(batchId, entities.map { it.toQueuedFix() })
    }

    override suspend fun markBatchAccepted(batchId: String) {
        requireInFlight(batchId)
        dao.accept(batchId)
    }

    override suspend fun markBatchFailedTransient(batchId: String) {
        requireInFlight(batchId, allowNoBatch = true)
        dao.failTransient(batchId)
    }

    override suspend fun markBatchRejected(batchId: String, offendingFixIds: Set<String>) {
        requireInFlight(batchId)
        dao.reject(batchId, offendingFixIds)
    }

    override suspend fun clearAll() {
        dao.clearAll()
    }

    /**
     * Mirrors [com.findly.android.queue.InMemoryFixQueueStore]'s `require(batch.batchId ==
     * batchId)` guard (specs/003 §10.2): a caller resolving a `batchId` that isn't the currently
     * frozen one is a programming error (a stale reference from a previous batch, e.g.), not a
     * legitimate race — [markBatchFailedTransient] alone tolerates "nothing in flight" (a no-op
     * either way), matching the in-memory implementation's own leniency there.
     */
    private suspend fun requireInFlight(batchId: String, allowNoBatch: Boolean = false) {
        val current = dao.currentBatchId()
        if (current == null && allowNoBatch) return
        require(current == batchId) { "batchId mismatch: expected $current, got $batchId" }
    }
}

private fun QueuedFix.toEntity(): FixEntity = FixEntity(
    fixId = fixId,
    recordedAt = recordedAt,
    lat = lat,
    lon = lon,
    accuracyM = accuracyM,
    altitudeM = altitudeM,
    speedMps = speedMps,
    bearingDeg = bearingDeg,
    batteryPct = batteryPct,
    source = source.toWireValue(),
    batchId = null,
)

private fun FixEntity.toQueuedFix(): QueuedFix = QueuedFix(
    fixId = fixId,
    recordedAt = recordedAt,
    lat = lat,
    lon = lon,
    accuracyM = accuracyM,
    altitudeM = altitudeM,
    speedMps = speedMps,
    bearingDeg = bearingDeg,
    batteryPct = batteryPct,
    source = FixSource.fromWireValue(source),
)
