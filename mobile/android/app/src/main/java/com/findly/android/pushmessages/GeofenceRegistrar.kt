package com.findly.android.pushmessages

import com.findly.android.network.dto.GeofenceDto

/**
 * Seam for registering platform geofences after a config re-sync (specs/009-device-runtime.md
 * §6.2) — every §6.2 trigger (first sync after sign-in, an ETag piggyback mismatch,
 * `GEOFENCE_CONFIG_CHANGED`, resume from pause, reboot/reinstall) ends up here via
 * [com.findly.android.location.settings.GeofenceConfigSyncCoordinator].
 * [com.findly.android.location.geofence.GeofencingClientManager] (A11) is the real,
 * `GeofencingClient`-backed implementation — full unregister-all/register-all replace, per-call,
 * capped by the caller at `features.limits.maxGeofences` before this is ever invoked. Do not
 * change this shape without checking every caller.
 */
fun interface GeofenceRegistrar {
    fun registerAll(geofences: List<GeofenceDto>, etag: String)
}
