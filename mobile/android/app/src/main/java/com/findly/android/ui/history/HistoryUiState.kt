package com.findly.android.ui.history

import com.findly.android.ui.onboarding.OnboardingVariant

/** A single stored history point (001-api-contract.md §5.3) — unlike the live-map's
 * [com.findly.android.ui.map.RosterDeviceUi], every field is guaranteed non-null at write
 * time. */
data class HistoryPointUi(
    val deviceId: String,
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val batteryPct: Int,
    val source: String,
)

/** State surfaced by [HistoryStateHolder] (specs/003-android-client.md §12's reserved `History`
 * destination, filled in by A2). [Idle] is the pre-query state (no date range/userId chosen yet)
 * — distinct from [Content] with an empty [Content.points], which means "query ran, nothing in
 * range." */
sealed class HistoryUiState {
    data object Idle : HistoryUiState()
    data object Loading : HistoryUiState()
    data class Error(val message: String) : HistoryUiState()
    data class Content(
        val points: List<HistoryPointUi>,
        val nextCursor: String?,
        val isLoadingMore: Boolean = false,
    ) : HistoryUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND`
     * on a query routes to Onboarding instead of the dead-end retryable [Error] card. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : HistoryUiState()
}
