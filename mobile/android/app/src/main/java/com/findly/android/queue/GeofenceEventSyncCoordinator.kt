package com.findly.android.queue

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.ports.GeofenceApi

/** The outcome of a single [GeofenceEventSyncCoordinator.syncOnce] call — deliberately mirrors
 * [SyncOutcome]'s shape (same downstream reaction mapping,
 * `com.findly.android.queue.worker.SyncOutcomeReactor.reactionForGeofenceEvents`). */
sealed class GeofenceEventSyncOutcome {
    data object NothingToSync : GeofenceEventSyncOutcome()

    /** 001-api-contract.md §7.3: the same piggyback shape as §5.1 (minus `lastKnownUpdated`) —
     * callers MUST apply [deviceSettings] and compare [geofenceEtag] against the cached one
     * (specs/009-device-runtime.md §6.3: "the device SHOULD notice the geofenceEtag mismatch...
     * and re-sync config"). */
    data class Synced(
        val accepted: Int,
        val duplicates: Int,
        val deviceSettings: DeviceSettingsSnapshot,
        val geofenceEtag: String,
    ) : GeofenceEventSyncOutcome()

    data object TransientFailure : GeofenceEventSyncOutcome()
    data class Paused(val syncIntervalMinutes: Int, val trackingEnabled: Boolean) : GeofenceEventSyncOutcome()
    data class OtherFailure(val error: ApiError) : GeofenceEventSyncOutcome()
}

/**
 * Ties [GeofenceEventQueueStore] + `GeofenceApi.reportGeofenceEvents` together
 * (001-api-contract.md §7.3), mirroring [LocationSyncCoordinator]'s role for the fix queue
 * (specs/003-android-client.md §10.3). Unlike location batches, §7.3 defines no per-event
 * rejection shape (no `details.fields` analog) — every failure other than `TRACKING_PAUSED` keeps
 * the batch frozen for an identical retry, the same "retry rather than silently drop" posture
 * [LocationSyncCoordinator.handleFailure]'s own `else` branch takes for any undocumented failure
 * shape.
 */
class GeofenceEventSyncCoordinator(
    private val queueStore: GeofenceEventQueueStore,
    private val geofenceApi: GeofenceApi,
    private val deviceId: String,
    private val maxBatchSize: Int = 20,
) {
    suspend fun syncOnce(): GeofenceEventSyncOutcome {
        val batch = queueStore.nextBatch(maxBatchSize) ?: return GeofenceEventSyncOutcome.NothingToSync

        val eventDtos = batch.events.map { it.toDto() }
        return when (val result = geofenceApi.reportGeofenceEvents(deviceId, eventDtos)) {
            is ApiResult.Success -> {
                queueStore.markBatchSent(batch.batchId)
                GeofenceEventSyncOutcome.Synced(
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

    private suspend fun handleFailure(batch: GeofenceEventBatch, error: ApiError): GeofenceEventSyncOutcome = when (error) {
        is ApiError.TrackingPaused -> {
            // §7.3: "Paused device -> 403 TRACKING_PAUSED" - pre-pause events are not this
            // coordinator's concern; the caller stops, and they stay queued for after resume.
            val settings = error.deviceSettings
            if (settings != null) {
                GeofenceEventSyncOutcome.Paused(settings.syncIntervalMinutes, settings.trackingEnabled)
            } else {
                GeofenceEventSyncOutcome.OtherFailure(error)
            }
        }

        is ApiError.NetworkFailure, is ApiError.InternalError -> {
            queueStore.markBatchFailedTransient(batch.batchId)
            GeofenceEventSyncOutcome.TransientFailure
        }

        else -> {
            // No per-event rejection shape is defined for this endpoint - keep retrying rather
            // than silently dropping detected transitions (009 §6.3 treats a lost transition as
            // a MUST-not, unlike a dropped mid-GPS-capture fix).
            queueStore.markBatchFailedTransient(batch.batchId)
            GeofenceEventSyncOutcome.OtherFailure(error)
        }
    }
}
