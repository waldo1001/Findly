package com.findly.android.queue.room

/**
 * A plain-JVM stand-in for the SQL table [FixQueueDao]'s primitive members would run against —
 * overrides only the `@Insert`/`@Query` primitives with an in-memory list, and inherits every
 * `@Transaction` composite method (`enqueueAndCap`, `freezeNextBatch`, `accept`, `reject`, …)
 * completely unchanged from the interface. That means the tests in this package exercise the
 * *exact same* business logic Room will run against real SQLite in production — see
 * [FixQueueDao]'s doc for the full rationale (this is how specs/009-device-runtime.md §2's
 * durable-queue correctness properties are verified without a `Context`/Robolectric/emulator).
 */
class FakeFixQueueDao : FixQueueDao {
    private var nextSeq = 0L
    private val rows = mutableListOf<FixEntity>()

    /** Test-only inspection hook — not part of the DAO's real surface. */
    fun snapshot(): List<FixEntity> = rows.toList()

    override suspend fun insert(entity: FixEntity) {
        require(rows.none { it.fixId == entity.fixId }) { "duplicate fixId ${entity.fixId}" }
        rows.add(entity.copy(seq = nextSeq++))
    }

    override suspend fun currentBatchId(): String? = rows.firstOrNull { it.batchId != null }?.batchId

    override suspend fun pendingFixesOrdered(): List<FixEntity> =
        rows.filter { it.batchId == null }.sortedBy { it.seq }

    override suspend fun fixesInBatch(batchId: String): List<FixEntity> =
        rows.filter { it.batchId == batchId }.sortedBy { it.seq }

    override suspend fun assignBatch(batchId: String, fixIds: List<String>) {
        val idSet = fixIds.toSet()
        for (i in rows.indices) {
            if (rows[i].fixId in idSet) rows[i] = rows[i].copy(batchId = batchId)
        }
    }

    override suspend fun deleteByIds(fixIds: List<String>) {
        val idSet = fixIds.toSet()
        rows.removeAll { it.fixId in idSet }
    }

    override suspend fun releaseBatch(batchId: String) {
        for (i in rows.indices) {
            if (rows[i].batchId == batchId) rows[i] = rows[i].copy(batchId = null)
        }
    }

    override suspend fun deleteAll() {
        rows.clear()
    }

    override suspend fun totalCount(): Int = rows.size

    override suspend fun oldestPendingIds(n: Int): List<String> =
        rows.filter { it.batchId == null }.sortedBy { it.seq }.take(n).map { it.fixId }
}
