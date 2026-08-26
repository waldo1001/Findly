package com.findly.android.ui.settings

import com.findly.android.ui.onboarding.OnboardingVariant

/** A family roster entry (001-api-contract.md §3.2/§3.5). */
data class MemberUi(
    val userId: String,
    val role: String,
    val displayName: String,
    val joinedAt: String?,
)

/** A family device with its roster context (§4.2). */
data class DeviceUi(
    val deviceId: String,
    val deviceName: String,
    val model: String,
    val platform: String,
    val syncIntervalMinutes: Int,
    val trackingEnabled: Boolean,
    val pushInvalid: Boolean,
    val ownerDisplayName: String,
    val lastSeenAt: String?,
)

/**
 * State surfaced by [SettingsStateHolder] (specs/003-android-client.md §12's reserved `Settings`
 * destination, filled in by A2 for §3.5/§3.6/§4.2/§4.3).
 *
 * @property myRole the caller's own role (`"parent"`/`"member"`, §1.6) — gates every mutation:
 *   member/role/device-settings edits and removal are parent-only (§3.5, §3.6, §4.3); a
 *   non-parent only ever reads this screen. [SettingsStateHolder.isParent] is the single place
 *   that reads this.
 */
sealed class SettingsUiState {
    data object Loading : SettingsUiState()
    data class Error(val message: String) : SettingsUiState()

    data class Content(
        val myRole: String,
        val members: List<MemberUi>,
        val devices: List<DeviceUi>,
        val isMutating: Boolean = false,
        val mutationError: String? = null,
    ) : SettingsUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND`
     * on [SettingsStateHolder.load] (which serves both the Devices and Family drawer destinations,
     * pending their A35 split out of this monolith) routes to Onboarding instead of the dead-end
     * retryable [Error] card. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : SettingsUiState()
}
