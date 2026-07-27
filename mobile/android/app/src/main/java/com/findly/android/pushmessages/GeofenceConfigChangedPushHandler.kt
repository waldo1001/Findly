package com.findly.android.pushmessages

import com.findly.android.location.settings.GeofenceConfigSyncCoordinator

/**
 * `GEOFENCE_CONFIG_CHANGED` (001-api-contract.md §8.4; specs/009-device-runtime.md §5.4): a thin
 * delegate onto the consolidated fetch-cache-register sequence
 * ([GeofenceConfigSyncCoordinator.sync], §6.2) — this push is just one of that class's five
 * triggers. `AppContainer` wires the real, ETag-cache-backed coordinator here now; A9's original
 * version of this handler (which had no cache to read/write yet and always fetched unconditionally)
 * predates A11 landing that cache.
 */
class GeofenceConfigChangedPushHandler(
    private val geofenceConfigSyncCoordinator: GeofenceConfigSyncCoordinator,
) {
    suspend fun handle() = geofenceConfigSyncCoordinator.sync()
}
