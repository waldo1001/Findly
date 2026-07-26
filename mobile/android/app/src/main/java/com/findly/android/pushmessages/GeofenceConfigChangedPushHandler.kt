package com.findly.android.pushmessages

import com.findly.android.network.ApiResult
import com.findly.android.network.ports.GeofenceApi

/**
 * `GEOFENCE_CONFIG_CHANGED` (001-api-contract.md §8.4; specs/009-device-runtime.md §5.4):
 * `GET /geofences` and, on a fresh (non-304) body, hand the config off to [geofenceRegistrar] for
 * platform re-registration (009 §6.2, A11 scope).
 *
 * No local cached ETag exists yet to pass as `If-None-Match` — no config cache has landed (A11
 * owns that per 009 §6.1) — so this always fetches unconditionally; a `304` (`null` body) or a
 * failed fetch are both silently ignored, same best-effort treatment as the piggyback path (009
 * §1).
 */
class GeofenceConfigChangedPushHandler(
    private val geofenceApi: GeofenceApi,
    private val geofenceRegistrar: GeofenceRegistrar,
) {
    suspend fun handle() {
        val result = geofenceApi.getGeofences(ifNoneMatch = null)
        if (result !is ApiResult.Success) return
        val etagged = result.data ?: return
        geofenceRegistrar.registerAll(etagged.value.geofences, etagged.etag)
    }
}
