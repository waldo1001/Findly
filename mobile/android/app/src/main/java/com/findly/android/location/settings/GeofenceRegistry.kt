package com.findly.android.location.settings

/**
 * The geofence-registration seam pause depends on (specs/009-device-runtime.md §4:
 * "...unregister all platform geofences"). [com.findly.android.location.geofence.GeofencingClientManager]
 * (A11) is the real, `GeofencingClient`-backed implementation — it also implements
 * [com.findly.android.pushmessages.GeofenceRegistrar], since a full replace ("unregister all,
 * register all", §6.2) is one platform-facing responsibility split across two seams for historical
 * reasons (pause only ever needs the unregister half).
 */
interface GeofenceRegistry {
    suspend fun unregisterAll()
}
