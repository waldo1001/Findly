package com.findly.android.location.settings

import com.findly.android.network.ApiResult
import com.findly.android.network.ports.GeofenceApi
import com.findly.android.pushmessages.GeofenceRegistrar

/**
 * The consolidated "fetch config (`If-None-Match`) -> update cache -> full re-register" sequence
 * (specs/009-device-runtime.md §6.2) that at least four of the five registration triggers need
 * verbatim: first config sync after sign-in, an observed `geofenceEtag` change ([syncIfEtagChanged]
 * — the piggyback of 001-api-contract.md §5.1/§7.3, or the `GEOFENCE_CONFIG_CHANGED` push), resume
 * from pause, and app cold start (covering reboot/reinstall, both of which lose OS-level geofence
 * registrations per §6.2 without changing anything server-side). One class instead of duplicating
 * this sequence at each call site — `AppContainer` wires a single instance.
 *
 * A `304` (config unchanged server-side, or a failed fetch) still ends in a full re-register from
 * whatever is cached: that's exactly what resume/cold-start need (the OS lost the registrations,
 * not the config), and it's a harmless, if occasionally redundant, no-op for the ETag-mismatch
 * trigger (which only calls [sync] after confirming a real mismatch, so a `304` there would only
 * happen on a race). Nothing cached yet and no fresh body available is a silent best-effort no-op —
 * the same treatment every other specs/009 §1/§5 best-effort path gives a failure.
 */
class GeofenceConfigSyncCoordinator(
    private val geofenceApi: GeofenceApi,
    private val geofenceConfigStore: GeofenceConfigStateStore,
    private val geofenceRegistrar: GeofenceRegistrar,
) {
    /** Unconditional full sync-and-register — every §6.2 trigger except the ETag-mismatch one
     * (which gates through [syncIfEtagChanged] first) calls this directly. */
    suspend fun sync() {
        val cached = geofenceConfigStore.current()
        when (val result = geofenceApi.getGeofences(ifNoneMatch = cached?.etag)) {
            is ApiResult.Success -> {
                val etagged = result.data
                if (etagged == null) {
                    // 304 - config unchanged; still re-register from cache.
                    registerFromCache(cached)
                } else {
                    val cap = result.features?.limits?.maxGeofences ?: etagged.value.geofences.size
                    val fresh = CachedGeofenceConfig(etagged.etag, etagged.value.geofences.take(cap))
                    geofenceConfigStore.update(fresh)
                    geofenceRegistrar.registerAll(fresh.geofences, fresh.etag)
                }
            }
            is ApiResult.Failure -> registerFromCache(cached)
        }
    }

    /** The §6.2 ETag-mismatch trigger (001-api-contract.md §5.1/§7.3's piggyback fires on *every*
     * flush): only calls [sync] when [observedEtag] actually differs from the cached one, so a
     * device that hasn't changed its config doesn't re-fetch the whole document on every single
     * sync cycle. */
    suspend fun syncIfEtagChanged(observedEtag: String) {
        if (geofenceConfigStore.current()?.etag == observedEtag) return
        sync()
    }

    private fun registerFromCache(cached: CachedGeofenceConfig?) {
        if (cached == null) return
        geofenceRegistrar.registerAll(cached.geofences, cached.etag)
    }
}
