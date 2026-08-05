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
 * doubles as both the **family-less home** ([Content.hasFamily] `false`) and, as of A21, the
 * **profile-less first-run home** ([ProfileNeeded]) — a signed-in user with no family and/or no
 * profile at all (001-api-contract.md §1.5) is no longer a dead end here, unlike every other
 * family-scoped feature screen.
 *
 * **A21 — distinct states, not a conflated one.** `PROFILE_NOT_FOUND` and `FAMILY_NOT_FOUND` used
 * to both collapse into `Content(hasFamily = false, ...)`, but they are materially different: a
 * profile-less caller can't even call `GET /groups` (001 §12.2 — "caller needs a profile"), so
 * that call must never be attempted for them, while a family-less-with-profile caller loads their
 * (possibly empty) group list normally. [ProfileNeeded] is the caller-has-no-profile-at-all state
 * (001 §1.5.3) — its own first-run UI offers the four bootstrap paths, none of which are the
 * doomed `GET /groups`. [Content.hasFamily] remains the family-less-with-profile signal, now
 * always paired with a real (successfully loaded) group list.
 */
sealed class GroupsListUiState {
    data object Loading : GroupsListUiState()

    /** No `Users` profile row exists yet (001 §1.5.3, `404 PROFILE_NOT_FOUND` on the family
     * probe) — `GET /groups` was never attempted (it would 404 too, §12.2). The four
     * profile-bootstrapping paths (create family §3.1, accept invite §3.4, create group §12.1,
     * join group §12.6) are this state's only ways forward. */
    data object ProfileNeeded : GroupsListUiState()

    data class Error(val message: String) : GroupsListUiState()

    data class Content(
        val groups: List<GroupSummaryUi>,
        /** The caller's own plan limits (001 §9) — `null` only if a `GET /groups` response
         * somehow carried no `features` (never happens in practice; every non-bare-204 envelope
         * has one, specs/003 §6.2). Threaded into `CreateGroupScreen` so the end-date picker can
         * bound itself by `maxGroupDurationDays` without a second network round trip. */
        val limits: PlanLimits?,
        /** `true` once `GET /families/me` succeeds for the caller (001 §1.5.4) — `false` for
         * `FAMILY_NOT_FOUND`. Gates the family-less informational card. A profile-less caller
         * never reaches `Content` at all (see [ProfileNeeded]), so `needsDisplayName` has no
         * meaning here anymore — every `Content` caller already has a profile. */
        val hasFamily: Boolean,
        val isRefreshing: Boolean = false,
    ) : GroupsListUiState()

    /** Threaded into `CreateGroupScreen`/`GroupJoinScreen` regardless of which entry point
     * reached them: [Content]'s ordinary create/join buttons (profile already exists,
     * [needsDisplayName] always `false`, [limits] from the just-loaded group list) or
     * [ProfileNeeded]'s first-run paths ([needsDisplayName] `true`, [limits] unavailable since
     * `GET /groups` was never called, [prefillDisplayName] carrying the name the user already
     * typed once on the first-run screen — see specs/003 §12.2/A21's "enter it once" flow). */
    data class CreateJoinContext(
        val limits: PlanLimits?,
        val needsDisplayName: Boolean,
        val prefillDisplayName: String = "",
    )
}
