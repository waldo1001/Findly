package com.findly.android.ui.groups

import com.findly.android.network.PlanLimits

/** The §12.2 list-item shape (001-api-contract.md §12.2). */
data class GroupSummaryUi(
    val groupId: String,
    val name: String,
    val endsAt: String,
    val expiryPolicy: String,
    val state: String,
    val role: String,
    val memberCount: Int,
    val code: String?,
)

/**
 * State surfaced by [GroupsListStateHolder] (specs/003-android-client.md §12.2). This screen
 * doubles as the **family-less home**: [Content.hasFamily] / [Content.needsDisplayName] let it
 * (and the create/join screens it launches) behave correctly for a signed-in user with no family
 * and/or no profile at all (001-api-contract.md §1.5) — previously a dead end, since every other
 * A2 feature screen is family-scoped.
 */
sealed class GroupsListUiState {
    data object Loading : GroupsListUiState()
    data class Error(val message: String) : GroupsListUiState()

    data class Content(
        val groups: List<GroupSummaryUi>,
        /** The caller's own plan limits (001 §9) — `null` only if a `GET /groups` response
         * somehow carried no `features` (never happens in practice; every non-bare-204 envelope
         * has one, specs/003 §6.2). Threaded into `CreateGroupScreen` so the end-date picker can
         * bound itself by `maxGroupDurationDays` without a second network round trip. */
        val limits: PlanLimits?,
        /** `true` once `GET /families/me` succeeds for the caller (001 §1.5.4) — `false` for
         * `FAMILY_NOT_FOUND` *or* `PROFILE_NOT_FOUND`. Gates the family-less informational card. */
        val hasFamily: Boolean,
        /** `true` only for `PROFILE_NOT_FOUND` (no profile at all yet) — `displayName` is then
         * REQUIRED on both `POST /groups` and `POST /groups/join` (001 §12.1/§12.6's bootstrap
         * rule); a caller with a profile (family-less or not) never needs it, since the server
         * defaults to the profile's own. */
        val needsDisplayName: Boolean,
        val isRefreshing: Boolean = false,
    ) : GroupsListUiState()
}
