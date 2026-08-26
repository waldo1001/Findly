package com.findly.android.ui.invites

/** The result of a successful `POST /invites/accept` (001-api-contract.md §3.4). */
data class AcceptedFamilyUi(val familyId: String, val familyName: String, val role: String)

/** State surfaced by [AcceptInviteStateHolder] (specs/010-app-shell-and-screen-ux.md §5.2). Split
 * out of the retired combined `InvitesUiState` (010 §6: create + accept become separate routes). */
data class AcceptInviteUiState(
    val isAcceptingInvite: Boolean = false,
    val acceptedFamily: AcceptedFamilyUi? = null,
    val acceptInviteError: String? = null,
)
