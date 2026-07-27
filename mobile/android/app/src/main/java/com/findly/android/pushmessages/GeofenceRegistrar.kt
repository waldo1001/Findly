package com.findly.android.pushmessages

import com.findly.android.network.dto.GeofenceDto

/**
 * Seam for registering platform geofences after a config re-sync (specs/009-device-runtime.md
 * §6.2) — triggered here by `GEOFENCE_CONFIG_CHANGED` (§5.4), and by every other §6.2 trigger
 * (first sync after sign-in, an ETag piggyback mismatch, resume from pause, reboot/reinstall)
 * once A11 wires the full lifecycle. A9 only needs the "config changed -> re-fetch -> hand off"
 * leg; the actual `GeofencingClient` registration (full unregister-all/register-all replace,
 * capped at `features.limits.maxGeofences`) is A11's job.
 *
 * TODO(A11): replace [UnimplementedGeofenceRegistrar] with a real implementation. Do not change
 * this shape without checking every caller.
 */
fun interface GeofenceRegistrar {
    fun registerAll(geofences: List<GeofenceDto>, etag: String)
}

/** A9's placeholder wiring target (`AppContainer`) until A11 lands the real implementation above —
 * a safe no-op so [GeofenceConfigChangedPushHandler] has something to call; the re-fetch itself
 * (this handler's real, tested logic) still happens regardless. */
object UnimplementedGeofenceRegistrar : GeofenceRegistrar {
    override fun registerAll(geofences: List<GeofenceDto>, etag: String) = Unit
}
