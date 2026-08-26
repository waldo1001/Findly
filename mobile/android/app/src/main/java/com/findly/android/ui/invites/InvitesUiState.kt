package com.findly.android.ui.invites

import com.findly.android.ui.onboarding.OnboardingVariant

/** The result of a successful `POST /families/me/invites` (001-api-contract.md §3.3). */
data class CreatedInviteUi(val inviteCode: String, val role: String, val expiresAt: String)

/** The result of a successful `POST /invites/accept` (§3.4). */
data class AcceptedFamilyUi(val familyId: String, val familyName: String, val role: String)

/**
 * State surfaced by [InvitesStateHolder] (specs/003-android-client.md §12; the create-invite and
 * accept-invite forms are independent actions on one screen, not mutually exclusive — a plain
 * data class rather than a sealed hierarchy, unlike every other A2 feature's `UiState`).
 */
data class InvitesUiState(
    val isCreatingInvite: Boolean = false,
    val createdInvite: CreatedInviteUi? = null,
    val createInviteError: String? = null,
    val isAcceptingInvite: Boolean = false,
    val acceptedFamily: AcceptedFamilyUi? = null,
    val acceptInviteError: String? = null,
    /** specs/010-app-shell-and-screen-ux.md §2.1: a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND`
     * on [InvitesStateHolder.createInvite] (parent-only, family-scoped, 001 §3.3) routes to
     * Onboarding instead of the dead-end retryable [createInviteError] chip. `acceptInvite` is
     * exempt — it is itself one of the four 001 §1.5.3 bootstrap endpoints and creates the
     * profile, so `PROFILE_NOT_FOUND` can never occur there, and it explicitly requires the
     * caller NOT already belong to a family, so `FAMILY_NOT_FOUND` is not a relevant outcome. */
    val createInviteRouteToOnboarding: OnboardingVariant? = null,
)
