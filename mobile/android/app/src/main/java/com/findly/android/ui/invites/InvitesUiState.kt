package com.findly.android.ui.invites

/** The result of a successful `POST /families/me/invites` (001-api-contract.md §3.3). */
data class CreatedInviteUi(val inviteCode: String, val role: String, val expiresAt: String)

/** The result of a successful `POST /invites/accept` (§3.4). */
data class AcceptedFamilyUi(val familyId: String, val familyName: String, val role: String)

/**
 * State surfaced by [InvitesStateHolder] (specs/003-android-client.md §12; the create-invite and
 * accept-invite forms are independent actions on one screen, not mutually exclusive — a plain
 * data class rather than a sealed hierarchy, unlike every other A2 feature's `UiState`).
 *
 * Neither sub-flow carries a specs/010-app-shell-and-screen-ux.md §2.1 routing outcome:
 * [createInvite][InvitesStateHolder.createInvite] is a mutation (`POST`), which §2.1 explicitly
 * excludes from the routing rule ("this rule is about the load path"), so its failures — including
 * `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` — render inline via [createInviteError] like every other
 * catalog code; `acceptInvite` is itself one of the four 001 §1.5.3 bootstrap endpoints and creates
 * the profile, so `PROFILE_NOT_FOUND` can never occur there, and it explicitly requires the caller
 * NOT already belong to a family, so `FAMILY_NOT_FOUND` is not a relevant outcome either.
 */
data class InvitesUiState(
    val isCreatingInvite: Boolean = false,
    val createdInvite: CreatedInviteUi? = null,
    val createInviteError: String? = null,
    val isAcceptingInvite: Boolean = false,
    val acceptedFamily: AcceptedFamilyUi? = null,
    val acceptInviteError: String? = null,
)
