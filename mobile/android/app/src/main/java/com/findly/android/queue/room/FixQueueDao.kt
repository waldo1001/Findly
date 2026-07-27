package com.findly.android.queue.room

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction

/**
 * Room DAO for the durable fix queue (specs/009-device-runtime.md §2). Deliberately a Kotlin
 * `interface` with a mix of Room-generated primitive members (`@Insert`/`@Query`, abstract — no
 * body) and plain default-body members annotated `@Transaction` that *compose* those primitives
 * into the actual queue business logic (freeze-on-first-ask batch identity, accept/reject/
 * transient-failure, the 1 000-cap oldest-first drop) — the same "combine several DAO calls into
 * one atomic unit" pattern Room's own docs recommend
 * (https://developer.android.com/training/data-storage/room/accessing-data#writing-transactions).
 *
 * This split is also what makes the queue's correctness properties testable on a plain JVM with
 * no Android framework, no `Context`, and no Robolectric (see [FakeFixQueueDao] in the test
 * source set): a test fake overrides only the primitive members with an in-memory list standing
 * in for the SQL table, and *inherits the composite `@Transaction` methods completely unchanged*
 * — so the exact same freeze/accept/reject/cap logic that Room will run against real SQLite in
 * production is what the test suite exercises. Only Room's own SQL execution of the primitives
 * (well-established, Google-maintained machinery) stays outside the unit-test boundary — the
 * same "thin, untested Android-framework sliver" scope line this codebase already draws
 * elsewhere (e.g. `AndroidDeviceInfoProvider`, specs/003-android-client.md §3).
 */
@Dao
interface FixQueueDao {

    @Insert
    suspend fun insert(entity: FixEntity)

    @Query("SELECT batchId FROM fixes WHERE batchId IS NOT NULL LIMIT 1")
    suspend fun currentBatchId(): String?

    @Query("SELECT * FROM fixes WHERE batchId IS NULL ORDER BY seq ASC")
    suspend fun pendingFixesOrdered(): List<FixEntity>

    @Query("SELECT * FROM fixes WHERE batchId = :batchId ORDER BY seq ASC")
    suspend fun fixesInBatch(batchId: String): List<FixEntity>

    @Query("UPDATE fixes SET batchId = :batchId WHERE fixId IN (:fixIds)")
    suspend fun assignBatch(batchId: String, fixIds: List<String>)

    @Query("DELETE FROM fixes WHERE fixId IN (:fixIds)")
    suspend fun deleteByIds(fixIds: List<String>)

    @Query("UPDATE fixes SET batchId = NULL WHERE batchId = :batchId")
    suspend fun releaseBatch(batchId: String)

    @Query("DELETE FROM fixes")
    suspend fun deleteAll()

    @Query("SELECT COUNT(*) FROM fixes")
    suspend fun totalCount(): Int

    @Query("SELECT fixId FROM fixes WHERE batchId IS NULL ORDER BY seq ASC LIMIT :n")
    suspend fun oldestPendingIds(n: Int): List<String>

    // ---- composite, transactional queue logic (specs/009-device-runtime.md §2) ----

    /**
     * Inserts [fix] then enforces the 1 000-fix cap (§2): when the total queue size exceeds
     * [cap], the **oldest** *not-yet-frozen* fixes are dropped first — an in-flight frozen batch
     * is never touched by the cap (it has already been handed to the network layer; freezing is
     * capped at ≤100 fixes per batch, so the pending pool always has enough non-frozen
     * candidates to trim in any realistic scenario). Returns the number of fixes dropped (0 if
     * none) so the caller can log a **count-only** debug line (never coordinates).
     */
    @Transaction
    suspend fun enqueueAndCap(fix: FixEntity, cap: Int): Int {
        insert(fix)
        val overflow = totalCount() - cap
        if (overflow <= 0) return 0
        val toDrop = oldestPendingIds(overflow)
        if (toDrop.isEmpty()) return 0
        deleteByIds(toDrop)
        return toDrop.size
    }

    /**
     * Freeze-on-first-ask (specs/003-android-client.md §10.2 rule 1): if a batch is already
     * frozen, returns its identical `batchId` + fix set unchanged (never reassigns, never mints
     * a second in-flight batch). Otherwise freezes the oldest ≤[maxSize] pending fixes under a
     * fresh id from [newBatchId] — assigning `batchId` to every one of those rows in the same
     * transaction that reads them is exactly the atomic "batchId + frozen fix set together"
     * property specs/009 §2 requires. `null` when nothing is pending (never an empty-array
     * batch, matching 001-api-contract.md §5.1: "empty → VALIDATION_FAILED").
     */
    @Transaction
    suspend fun freezeNextBatch(maxSize: Int, newBatchId: suspend () -> String): Pair<String, List<FixEntity>>? {
        val existing = currentBatchId()
        if (existing != null) {
            return existing to fixesInBatch(existing)
        }
        val pending = pendingFixesOrdered()
        if (pending.isEmpty()) return null
        val slice = pending.take(maxSize)
        val batchId = newBatchId()
        assignBatch(batchId, slice.map { it.fixId })
        return batchId to slice.map { it.copy(batchId = batchId) }
    }

    /** Any 2xx response (specs/003 §10.2 rule 2) — removes exactly the batch's fixes, permanently. */
    @Transaction
    suspend fun accept(batchId: String) {
        val fixes = fixesInBatch(batchId)
        if (fixes.isEmpty()) return
        deleteByIds(fixes.map { it.fixId })
    }

    /**
     * Definitive 4xx (specs/003 §10.2 rule 4) — drops only the named offenders and un-freezes
     * the remainder (clears their `batchId`), so they're eligible for a **new** `batchId` on the
     * next [freezeNextBatch] call.
     */
    @Transaction
    suspend fun reject(batchId: String, offendingFixIds: Set<String>) {
        if (offendingFixIds.isNotEmpty()) deleteByIds(offendingFixIds.toList())
        releaseBatch(batchId)
    }

    /** Network error / 5xx (specs/003 §10.2 rule 3) — no-op on the pending pool; the batch stays
     * frozen under the same `batchId` for an identical retry. Kept as an explicit method (rather
     * than the caller doing nothing) so the "changes nothing" contract has one obvious home and
     * a name that shows up in a stack trace. */
    @Suppress("UNUSED_PARAMETER")
    suspend fun failTransient(batchId: String) {
        // Intentionally empty.
    }

    /** Total fixes in the store, pending **and** frozen-in-flight alike (specs/003 §10.1's
     * `pendingCount()` counts everything not yet resolved — mirrors [com.findly.android.queue.InMemoryFixQueueStore]). */
    suspend fun pendingCount(): Int = totalCount()

    /** Drops every row unconditionally (specs/008-privacy-endpoints.md §4.4 local-state wipe). */
    suspend fun clearAll() = deleteAll()
}
