package com.findly.android.location.settings

/**
 * The geofence-registration seam pause depends on (specs/009-device-runtime.md §4:
 * "...unregister all platform geofences"). Registration itself — the `GeofencingClient` calls,
 * the synced-config cache, the 20-region cap, full-replace re-registration (§6) — is **A11
 * scope**, deliberately not implemented here. [NoopGeofenceRegistry] is a documented stand-in so
 * pause's own contract is complete today; A11 replaces the wiring with a real implementation
 * behind this unchanged interface, same pattern as `StubPushTokenProvider` (specs/003 §9).
 */
interface GeofenceRegistry {
    suspend fun unregisterAll()
}

/** TODO(A11): replace with a `GeofencingClient`-backed implementation (specs/009 §6.2). */
class NoopGeofenceRegistry : GeofenceRegistry {
    override suspend fun unregisterAll() = Unit
}
