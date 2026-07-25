package com.findly.android.ui.map

/** One device's roster entry (001-api-contract.md §5.2). `lat`/`lon`/`recordedAt`/`isStale` are
 * `null` for a device that has never reported — the "no location yet" state the spec requires
 * both apps to render identically. */
data class RosterDeviceUi(
    val deviceId: String,
    val deviceName: String,
    val lat: Double?,
    val lon: Double?,
    val recordedAt: String?,
    val batteryPct: Int?,
    val trackingEnabled: Boolean,
    val syncIntervalMinutes: Int,
    val isStale: Boolean?,
) {
    val hasLocation: Boolean get() = lat != null && lon != null
}

/** A family member and their devices (§5.2 — every member always appears, even with `devices:
 * []`). */
data class RosterMemberUi(
    val userId: String,
    val displayName: String,
    val devices: List<RosterDeviceUi>,
)

/** State surfaced by [MapStateHolder] (specs/003-android-client.md §12's reserved `Map`
 * destination, filled in by A2). */
sealed class MapUiState {
    data object Loading : MapUiState()
    data class Error(val message: String) : MapUiState()
    data class Content(val members: List<RosterMemberUi>, val isRefreshing: Boolean = false) : MapUiState()
}
