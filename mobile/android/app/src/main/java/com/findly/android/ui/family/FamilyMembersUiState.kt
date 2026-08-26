package com.findly.android.ui.family

import com.findly.android.ui.onboarding.OnboardingVariant

/** A family roster entry (001-api-contract.md §3.2/§3.5). */
data class MemberUi(
    val userId: String,
    val role: String,
    val displayName: String,
    val joinedAt: String?,
)

/**
 * State surfaced by [FamilyMembersStateHolder] (specs/010-app-shell-and-screen-ux.md §4.1's
 * `Family` route, extracted from the retired `SettingsStateHolder`; wire shapes
 * specs/001-api-contract.md §3.2/§3.5/§3.6). Mirrors iOS's `FamilyMembersViewModel` shape — a
 * single, shared [Content.mutationError] (not per-row), since specs/010 §4.2's per-card error
 * placement rule is specific to the Devices screen's cards, not this roster.
 */
sealed class FamilyMembersUiState {
    data object Loading : FamilyMembersUiState()
    data class Error(val message: String) : FamilyMembersUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/
     * `FAMILY_NOT_FOUND` on [FamilyMembersStateHolder.load] (`GET /families/me` is family-scoped,
     * 001 §1.5.4/§3.2) routes to Onboarding instead of the dead-end retryable [Error] card. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : FamilyMembersUiState()

    data class Content(
        val familyName: String,
        val myRole: String,
        val members: List<MemberUi>,
        val isMutating: Boolean = false,
        val mutationError: String? = null,
    ) : FamilyMembersUiState()
}
