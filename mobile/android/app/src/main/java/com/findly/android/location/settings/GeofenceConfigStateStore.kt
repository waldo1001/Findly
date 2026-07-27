package com.findly.android.location.settings

import com.findly.android.network.dto.GeofenceDto

/**
 * The cached geofence config document + its ETag (specs/009-device-runtime.md §6.1: "The client
 * caches the document and its ETag"). Storing the actual [geofences] list — not just the ETag — is
 * what lets [GeofenceConfigSyncCoordinator] re-register from a `304 Not Modified` (config
 * unchanged) or a failed fetch: the resume-from-pause and cold-start triggers (§6.2) need the
 * platform registrations rebuilt even when nothing changed server-side, since it's the OS-level
 * registration that was lost, not the config.
 */
data class CachedGeofenceConfig(val etag: String, val geofences: List<GeofenceDto>)

/**
 * Persists [CachedGeofenceConfig] across process restarts (specs/009-device-runtime.md §6.1) — the
 * same interface + real/fake split as [DeviceSettingsStateStore]
 * (`SharedPreferencesGeofenceConfigStateStore` is the real implementation).
 */
interface GeofenceConfigStateStore {
    suspend fun current(): CachedGeofenceConfig?
    suspend fun update(config: CachedGeofenceConfig)

    /** Drops the cached document/ETag unconditionally — used only by a full local-state wipe
     * after account deletion (specs/008-privacy-endpoints.md §4.4; specs/003-android-client.md
     * §12.4: "any cached config/ETags"), same as [com.findly.android.queue.FixQueueStore.clearAll]. */
    suspend fun clear()
}
