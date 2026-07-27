package com.findly.android.queue.room

/**
 * A plain-JVM stand-in for the SQL table [GeofenceEventDao]'s primitive members would run
 * against — overrides only the primitives with an in-memory list and inherits every
 * `@Transaction` composite method unchanged, exactly the [FakeFixQueueDao] pattern (see its doc
 * for the full rationale).
 */
class FakeGeofenceEventDao : GeofenceEventDao {
    private var nextSeq = 0L
    private val rows = mutableListOf<GeofenceEventEntity>()

    fun snapshot(): List<GeofenceEventEntity> = rows.toList()

    override suspend fun insert(entity: GeofenceEventEntity) {
        require(rows.none { it.eventId == entity.eventId }) { "duplicate eventId ${entity.eventId}" }
        rows.add(entity.copy(seq = nextSeq++))
    }

    override suspend fun currentBatchId(): String? = rows.firstOrNull { it.batchId != null }?.batchId

    override suspend fun pendingEventsOrdered(): List<GeofenceEventEntity> =
        rows.filter { it.batchId == null }.sortedBy { it.seq }

    override suspend fun eventsInBatch(batchId: String): List<GeofenceEventEntity> =
        rows.filter { it.batchId == batchId }.sortedBy { it.seq }

    override suspend fun assignBatch(batchId: String, eventIds: List<String>) {
        val idSet = eventIds.toSet()
        for (i in rows.indices) {
            if (rows[i].eventId in idSet) rows[i] = rows[i].copy(batchId = batchId)
        }
    }

    override suspend fun deleteByIds(eventIds: List<String>) {
        val idSet = eventIds.toSet()
        rows.removeAll { it.eventId in idSet }
    }

    override suspend fun deleteAll() {
        rows.clear()
    }

    override suspend fun totalCount(): Int = rows.size
}
