package com.findly.android.ui.devices

import com.findly.android.network.PlanLimits
import com.findly.android.ui.onboarding.OnboardingVariant

/**
 * One device card (specs/010-app-shell-and-screen-ux.md §4.2). [renameDraft] is the card's own
 * in-progress rename text — independent of [deviceName] until a rename actually commits — so
 * typing into one card's rename field never touches any other card's state, and toggling tracking
 * or changing the sync interval on this same card never clobbers an in-progress rename draft
 * (only a successful rename ever overwrites it, back to the server's echoed value). [isMutating]/
 * [error] are per-card (§4.2: "Errors from this card's mutations render on this card, not pooled
 * at the top of the list" — the exact iOS `lastActionError` pattern §4.2 retires).
 */
data class DeviceCardUi(
    val deviceId: String,
    val deviceName: String,
    val model: String,
    val platform: String,
    val syncIntervalMinutes: Int,
    val trackingEnabled: Boolean,
    val pushInvalid: Boolean,
    val ownerDisplayName: String,
    val lastSeenAt: String?,
    val renameDraft: String = deviceName,
    val isMutating: Boolean = false,
    val error: String? = null,
)

/**
 * State surfaced by [DevicesStateHolder] (specs/010-app-shell-and-screen-ux.md §4; wire shapes
 * specs/001-api-contract.md §4.2/§4.3).
 */
sealed class DevicesUiState {
    data object Loading : DevicesUiState()
    data class Error(val message: String) : DevicesUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND` on
     * [DevicesStateHolder.load] routes to Onboarding instead of the dead-end retryable [Error]
     * card. `GET /devices` works without a family (001 §1.5.4/§4), so a confirmed
     * `FAMILY_NOT_FOUND` is not actually reachable here in practice — the shared classifier is
     * applied anyway, defensively, the same way iOS's `DeviceSettingsViewModel` does. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : DevicesUiState()

    data class Content(
        val devices: List<DeviceCardUi>,
        /** The caller's own plan limits (001 §9) — threaded straight to [SyncIntervalOptions.build]
         * so the dropdown's floor is always read from `features`, never hardcoded (`CLAUDE.md`'s
         * subscription-readiness rule). `null` only if a `GET /devices` response somehow carried
         * no `features` (never happens in practice, specs/003 §6.2). */
        val limits: PlanLimits?,
    ) : DevicesUiState()
}
