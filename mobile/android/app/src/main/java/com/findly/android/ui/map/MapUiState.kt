package com.findly.android.ui.map

import com.findly.android.ui.onboarding.OnboardingVariant

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

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND`
     * on this load routes to Onboarding instead of rendering a retryable [Error] card. Map is the
     * NavHost root, so this is also what the launch gate's own routing degrades to defensively if
     * the family/profile state changes out from under an already-open Map (e.g. the family was
     * deleted mid-session). */
    data class RouteToOnboarding(val variant: OnboardingVariant) : MapUiState()
}
