package com.findly.android.ui.invites

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
)
