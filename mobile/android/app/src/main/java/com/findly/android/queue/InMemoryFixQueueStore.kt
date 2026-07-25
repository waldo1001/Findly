package com.findly.android.queue

import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The A1 fix-queue implementation. Persistent (Room) storage is an **explicit, documented
 * deferral** (specs/003-android-client.md §10.4 — no Android/Gradle toolchain here to
 * compile-check a Room + KSP annotation-processing setup), not an oversight: this class
 * satisfies the exact [FixQueueStore] interface a persistent implementation will later replace
 * it behind, with zero call-site changes.
 */
class InMemoryFixQueueStore(
    private val batchIdGenerator: () -> String = { UUID.randomUUID().toString() },
) : FixQueueStore {

    private val mutex = Mutex()
    private val pending = mutableListOf<QueuedFix>()
    private var inFlight: FixBatch? = null

    override suspend fun enqueue(fix: QueuedFix) {
        mutex.withLock { pending.add(fix) }
    }

    override suspend fun pendingCount(): Int = mutex.withLock { pending.size }

    override suspend fun nextBatch(maxSize: Int): FixBatch? = mutex.withLock {
        inFlight?.let { return@withLock it }
        if (pending.isEmpty()) return@withLock null
        val slice = pending.take(maxSize)
        val batch = FixBatch(batchIdGenerator(), slice)
        inFlight = batch
        batch
    }

    override suspend fun markBatchAccepted(batchId: String) {
        mutex.withLock {
            val batch = inFlight ?: return@withLock
            require(batch.batchId == batchId) {
                "batchId mismatch: expected ${batch.batchId}, got $batchId"
            }
            val acceptedIds = batch.fixes.map { it.fixId }.toSet()
            pending.removeAll { it.fixId in acceptedIds }
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

    override suspend fun markBatchRejected(batchId: String, offendingFixIds: Set<String>) {
        mutex.withLock {
            val batch = inFlight ?: return@withLock
            require(batch.batchId == batchId) {
                "batchId mismatch: expected ${batch.batchId}, got $batchId"
            }
            pending.removeAll { it.fixId in offendingFixIds }
            inFlight = null
        }
    }
}
