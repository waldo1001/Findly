package com.findly.android.queue

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.ports.LocationsApi

/** The outcome of a single [LocationSyncCoordinator.syncOnce] call. */
sealed class SyncOutcome {
    data object NothingToSync : SyncOutcome()

    /** 001-api-contract.md §5.1: **every** accepted response carries the current
     * `deviceSettings` + `geofenceEtag` piggyback — this is the mandatory, primary way settings
     * and geofence changes reach the device (specs/009-device-runtime.md §1), not an optional
     * extra. Callers MUST apply [deviceSettings] on every `Synced` outcome, not just [Paused]. */
    data class Synced(
        val accepted: Int,
        val duplicates: Int,
        val deviceSettings: DeviceSettingsSnapshot,
        val geofenceEtag: String,
    ) : SyncOutcome()

    data object TransientFailure : SyncOutcome()
    data class Rejected(val droppedFixIds: Set<String>) : SyncOutcome()
    data class Paused(val syncIntervalMinutes: Int, val trackingEnabled: Boolean) : SyncOutcome()
    data class OtherFailure(val error: ApiError) : SyncOutcome()
}

/**
 * Ties [FixQueueStore] + [LocationsApi] together, implementing 001-api-contract.md §5.1's
 * `batchId` idempotency model end to end (specs/003-android-client.md §10.3).
 */
class LocationSyncCoordinator(
    private val queueStore: FixQueueStore,
    private val locationsApi: LocationsApi,
    private val deviceId: String,
    private val maxBatchSize: Int = 100,
) {
    suspend fun syncOnce(): SyncOutcome {
        val batch = queueStore.nextBatch(maxBatchSize) ?: return SyncOutcome.NothingToSync

        val fixDtos = batch.fixes.map { it.toDto() }
        return when (val result = locationsApi.reportLocations(deviceId, batch.batchId, fixDtos)) {
            is ApiResult.Success -> {
                queueStore.markBatchAccepted(batch.batchId)
                SyncOutcome.Synced(
                    accepted = result.data.accepted,
                    duplicates = result.data.duplicates,
                    deviceSettings = DeviceSettingsSnapshot(
                        result.data.deviceSettings.syncIntervalMinutes,
                        result.data.deviceSettings.trackingEnabled,
                    ),
                    geofenceEtag = result.data.geofenceEtag,
                )
            }
            is ApiResult.Failure -> handleFailure(batch, result.error)
        }
    }

    private suspend fun handleFailure(batch: FixBatch, error: ApiError): SyncOutcome = when (error) {
        is ApiError.TrackingPaused -> {
            // Paused devices are not the queue's concern (§5.1) - the caller stops the periodic
            // worker; fixes recorded before the pause stay queued, untouched, for after resume.
            val settings = error.deviceSettings
            if (settings != null) {
                SyncOutcome.Paused(settings.syncIntervalMinutes, settings.trackingEnabled)
            } else {
                SyncOutcome.OtherFailure(error)
            }
        }

        is ApiError.ValidationFailed -> {
            val offendingFixIds = offendingFixIdsFrom(batch, error.fields)
            queueStore.markBatchRejected(batch.batchId, offendingFixIds)
            SyncOutcome.Rejected(offendingFixIds)
        }

        is ApiError.LocationBatchTooLarge -> {
            // Definitive 4xx per §5.1 - the batch is dead. Our own nextBatch(maxSize) never
            // actually produces >100-fix batches, so this is defensive-only: un-freeze so a
            // fresh batchId gets assigned next time, dropping nothing specific.
            queueStore.markBatchRejected(batch.batchId, emptySet())
            SyncOutcome.Rejected(emptySet())
        }

        is ApiError.NetworkFailure, is ApiError.InternalError -> {
            queueStore.markBatchFailedTransient(batch.batchId)
            SyncOutcome.TransientFailure
        }

        else -> {
            // Any other 4xx (e.g. AUTH_FORBIDDEN, DEVICE_NOT_FOUND) is not one of §5.1's
            // documented "definitive rejection" shapes - treat as transient/retryable rather
            // than silently dropping fixes.
            queueStore.markBatchFailedTransient(batch.batchId)
            SyncOutcome.OtherFailure(error)
        }
    }

    private fun offendingFixIdsFrom(batch: FixBatch, fields: List<String>?): Set<String> {
        if (fields.isNullOrEmpty()) return emptySet()
        val indices = fields.mapNotNull { fieldPath ->
            FIXES_INDEX_REGEX.find(fieldPath)?.groupValues?.get(1)?.toIntOrNull()
        }
        return indices.mapNotNull { index -> batch.fixes.getOrNull(index)?.fixId }.toSet()
    }

    private companion object {
        val FIXES_INDEX_REGEX = Regex("""fixes\[(\d+)]""")
    }
}
