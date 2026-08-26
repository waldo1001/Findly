package com.findly.android.ui.invites

/** The result of a successful `POST /invites/accept` (001-api-contract.md §3.4). */
data class AcceptedFamilyUi(val familyId: String, val familyName: String, val role: String)

/** State surfaced by [AcceptInviteStateHolder] (specs/010-app-shell-and-screen-ux.md §5.2). Split
 * out of the retired combined `InvitesUiState` (010 §6: create + accept become separate routes).
 *
 * @property displayNameFallback the caller's own profile `displayName`, resolved (review-round
 *   fix) from `GET /devices`' first entry's `ownerDisplayName` when the screen wasn't reached
 *   with an explicit prefill (001 §4.2: "A family-less caller gets their own devices only (same
 *   response shape; `ownerDisplayName` = their profile `displayName`)" — no new endpoint, no
 *   mutation). `null` until [AcceptInviteStateHolder.loadDisplayNameFallback] resolves it, or
 *   forever if the caller has no devices yet / the call fails — this is a best-effort
 *   convenience prefill, never a blocker on the join flow. */
data class AcceptInviteUiState(
    val isAcceptingInvite: Boolean = false,
    val acceptedFamily: AcceptedFamilyUi? = null,
    val acceptInviteError: String? = null,
    val displayNameFallback: String? = null,
)
