package com.findly.android.ui.invites

/** The result of a successful `POST /families/me/invites` (001-api-contract.md §3.3). */
data class CreatedInviteUi(val inviteCode: String, val role: String, val expiresAt: String)

/** State surfaced by [CreateInviteStateHolder] (specs/010-app-shell-and-screen-ux.md §5.1). Split
 * out of the retired combined `InvitesUiState` (010 §6: create + accept become separate routes). */
data class CreateInviteUiState(
    val isCreatingInvite: Boolean = false,
    val createdInvite: CreatedInviteUi? = null,
    val createInviteError: String? = null,
)
