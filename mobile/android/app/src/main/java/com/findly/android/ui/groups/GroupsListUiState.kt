package com.findly.android.ui.groups

import com.findly.android.network.PlanLimits
import com.findly.android.ui.onboarding.OnboardingVariant

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
 * doubles as the **family-less home** ([Content.hasFamily] `false`) — a signed-in user with no
 * family (001-api-contract.md §1.5.4) is no longer a dead end here, unlike every other
 * family-scoped feature screen; Group screens only need a profile (specs/010-app-shell-and-
 * screen-ux.md §2.1), so `FAMILY_NOT_FOUND` never routes away from this one.
 *
 * **A21 → retired by 010 §2.1/§6.** A profile-less caller can't even call `GET /groups` (001
 * §12.2 — "caller needs a profile"), so that call must never be attempted for them; this used to
 * be its own first-run [ProfileNeeded] state with the four bootstrap paths inlined here — 010 §6
 * retires it in favor of the shared [RouteToOnboarding] outcome (profile-less variant), which
 * routes to the new Onboarding screen instead. [Content.hasFamily] remains the
 * family-less-with-profile signal, always paired with a real (successfully loaded) group list.
 */
sealed class GroupsListUiState {
    data object Loading : GroupsListUiState()

    data class Error(val message: String) : GroupsListUiState()

    /** specs/010-app-shell-and-screen-ux.md §2.1/§6: a confirmed `PROFILE_NOT_FOUND` — on either
     * the family probe or (defensively) `GET /groups` itself — routes to Onboarding instead of
     * the retired [ProfileNeeded] first-run state or a dead-end [Error] card. `FAMILY_NOT_FOUND`
     * never produces this outcome here (Group screens only need a profile, §2.1) — it stays
     * [Content.hasFamily] `false`, as before. */
    data class RouteToOnboarding(val variant: OnboardingVariant) : GroupsListUiState()

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
     * [needsDisplayName] always `false`, [limits] from the just-loaded group list) or the 010
     * §2.2 Onboarding (profile-less variant)'s first-run paths ([needsDisplayName] `true`,
     * [limits] unavailable since `GET /groups` was never called, [prefillDisplayName] carrying
     * the name the user already typed once on Onboarding — the A21 "enter it once" flow,
     * unchanged by the 010 move). */
    data class CreateJoinContext(
        val limits: PlanLimits?,
        val needsDisplayName: Boolean,
        val prefillDisplayName: String = "",
    )
}
