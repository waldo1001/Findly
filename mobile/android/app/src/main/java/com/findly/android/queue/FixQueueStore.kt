package com.findly.android.queue

/**
 * The offline fix-queue contract (specs/003-android-client.md §10.2; 001-api-contract.md §5.1's
 * `batchId` idempotency model). [InMemoryFixQueueStore] is the A1 implementation — see specs/003
 * §10.4 for the explicit deferral of a persistent (Room) implementation.
 */
interface FixQueueStore {
    suspend fun enqueue(fix: QueuedFix)
    suspend fun pendingCount(): Int

    /**
     * Freezes (or returns the already-frozen) oldest ≤[maxSize] pending fixes under a stable
     * `batchId` — repeated calls before the batch is resolved return the identical `batchId` +
     * fix set (§10.2 rule 1, the retry-identical-content requirement). `null` when nothing is
     * pending (never an empty-array batch).
     */
    suspend fun nextBatch(maxSize: Int = 100): FixBatch?

    /** Any 2xx response, regardless of the `accepted`/`duplicates` split (§10.2 rule 2). */
    suspend fun markBatchAccepted(batchId: String)

    /** Network error / 5xx — the batch stays frozen for an identical retry (§10.2 rule 3). */
    suspend fun markBatchFailedTransient(batchId: String)

    /**
     * Definitive 4xx (001 §5.1: "no marker was written — the batch is dead") — drops only the
     * named offenders; the remainder is eligible for a **new** `batchId` on the next
     * [nextBatch] call (§10.2 rule 4).
     */
    suspend fun markBatchRejected(batchId: String, offendingFixIds: Set<String>)
}
