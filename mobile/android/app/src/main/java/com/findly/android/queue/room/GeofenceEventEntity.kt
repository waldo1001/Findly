package com.findly.android.queue.room

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * The Room row shape backing [GeofenceEventDao] (specs/009-device-runtime.md §6.3). `seq` is a
 * plain auto-increment rowid preserving insertion order — `eventId` (client-generated UUIDv4,
 * 001-api-contract.md §7.3) is the event's real, server-idempotent identity. `batchId` is a
 * client-local grouping only (never sent over the wire — §7.3's request body has no `batchId`
 * field) that exists purely so a transient-failure retry resends the identical event set, mirroring
 * [com.findly.android.queue.room.FixEntity]'s `batchId` for the same reason.
 */
@Entity(
    tableName = "geofence_events",
    indices = [Index(value = ["eventId"], unique = true), Index(value = ["batchId"])],
)
data class GeofenceEventEntity(
    @PrimaryKey(autoGenerate = true) val seq: Long = 0,
    val eventId: String,
    val geofenceId: String,
    val transition: String,
    val recordedAt: String,
    val batchId: String?,
)
