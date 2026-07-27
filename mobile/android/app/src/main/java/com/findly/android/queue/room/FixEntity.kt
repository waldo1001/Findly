package com.findly.android.queue.room

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * The Room row shape backing [FixQueueDao] (specs/009-device-runtime.md §2). `seq` is a
 * plain auto-increment rowid used only to preserve insertion order — `fixId` (client-generated
 * UUIDv4, specs/003-android-client.md §10.1) is the fix's real, unique identity.
 *
 * `batchId` is the crux of the durable-queue correctness property this task exists for: a
 * `null` `batchId` means "still pending, not yet frozen into a batch"; a non-null `batchId`
 * means "frozen into the in-flight [com.findly.android.queue.FixBatch] with that id". Storing
 * `batchId` **on the fix row itself** — persisted in the same table, updated in the same Room
 * transaction that assigns it (see [FixQueueDao.freezeNextBatch]) — is what makes the frozen
 * batch identity and its exact fix set durable as **one atomic unit**: a process death
 * immediately before or after that transaction commits leaves either the old state (nothing
 * frozen) or the new one (exactly those fixes frozen under that batchId), never a partial or
 * inconsistent state. A design that instead kept `batchId` only in memory (or recomputed "the
 * next 100 pending fixes" freshly after every restart) would risk minting a **new** `batchId`
 * for fixes the server may already have accepted under the old one after a crash-mid-request —
 * defeating 001-api-contract.md §5.1's batch-level idempotency and double-counting history
 * server-side (000-overview.md §D7). That failure mode is exactly what this schema avoids.
 */
@Entity(
    tableName = "fixes",
    indices = [Index(value = ["fixId"], unique = true), Index(value = ["batchId"])],
)
data class FixEntity(
    @PrimaryKey(autoGenerate = true) val seq: Long = 0,
    val fixId: String,
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val altitudeM: Double?,
    val speedMps: Double?,
    val bearingDeg: Double?,
    val batteryPct: Int,
    val source: String,
    val batchId: String?,
)
