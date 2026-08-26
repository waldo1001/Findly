package com.findly.android.ui.locate

import com.findly.android.ui.onboarding.OnboardingVariant

/** The instant "last known" answer that comes back with the create call (001-api-contract.md
 * §6.1) — `null` if the target has never reported. */
data class LastKnownUi(
    val deviceId: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val recordedAt: String,
)

/** The high-accuracy fix the target device supplies on fulfillment (§6.2/§6.3) — present only
 * once [LocateUiState.Terminal.status] is `"fulfilled"`. */
data class LocateFixUi(
    val deviceId: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val recordedAt: String,
    val batteryPct: Int,
)

/** State surfaced by [LocateStateHolder] (specs/003-android-client.md §12's reserved `Locate`
 * destination, filled in by A2). §6.2's terminal statuses are `"fulfilled"`, `"expired"`,
 * `"pushFailed"` — [Polling] covers `"pending"`. */
sealed class LocateUiState {
    data object Idle : LocateUiState()
    data class Error(val message: String) : LocateUiState()

    data class Polling(
        val requestId: String,
        val lastKnown: LastKnownUi?,
        val expiresAt: String,
    ) : LocateUiState()

    data class Terminal(
        val requestId: String,
        val status: String,
        val fix: LocateFixUi?,
        val lastKnown: LastKnownUi?,
    ) : LocateUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND`
     * on the create/poll call (Locate has no separate eager load — this *is* its load path)
     * routes to Onboarding instead of the dead-end retryable [Error] card. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : LocateUiState()
}
