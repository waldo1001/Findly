package com.findly.android.ui.invites

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.ports.DevicesApi
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The accept-invite ("Join a family") screen's pure state machine (001-api-contract.md §3.4,
 * specs/010-app-shell-and-screen-ux.md §5.2). Split out of the retired combined
 * `InvitesStateHolder` (010 §6) — this is the "accept an invite" half; [CreateInviteStateHolder]
 * is the other.
 *
 * Every [acceptInvite] call runs [inviteCode] through [FamilyInviteCodeSanitizer] **before**
 * touching the network — the same "validate-then-sanitize-then-call" shape
 * [com.findly.android.ui.groups.GroupJoinStateHolder.join] already uses for group codes (010
 * §5.2: "normalization before the network call is unchanged"), so a typed, pasted, or deep-link-
 * prefilled code all converge on the identical gate; an unparsable code never leaves the device.
 */
class AcceptInviteStateHolder(private val familyApi: FamilyApi, private val devicesApi: DevicesApi) {

    private val _state = MutableStateFlow(AcceptInviteUiState())
    val state: StateFlow<AcceptInviteUiState> = _state.asStateFlow()

    fun validate(inviteCode: String, displayName: String): String? = when {
        FamilyInviteCodeSanitizer.sanitize(inviteCode) == null -> "Enter a valid 8-character invite code"
        displayName.isBlank() -> "Enter a display name"
        else -> null
    }

    /** §3.4 — caller MUST NOT already belong to a family;
     * `INVITE_INVALID`/`INVITE_ALREADY_USED`/`INVITE_EXPIRED`/`FAMILY_ALREADY_MEMBER` all surface
     * as an ordinary [AcceptInviteUiState.acceptInviteError]. `displayName` is required
     * unconditionally server-side (`backend/src/http/validate.ts`) — a blank value never reaches
     * the network, mirroring [com.findly.android.ui.family.CreateFamilyStateHolder.validate]'s
     * same unconditional "gate before any network call" convention (this is one of the four
     * equally-weighted first-run bootstrap paths off Onboarding's profile-less variant,
     * specs/010-app-shell-and-screen-ux.md §2.2). */
    suspend fun acceptInvite(inviteCode: String, displayName: String) {
        val problem = validate(inviteCode, displayName)
        if (problem != null) {
            _state.value = _state.value.copy(acceptInviteError = problem)
            return
        }

        _state.value = _state.value.copy(isAcceptingInvite = true, acceptInviteError = null)
        val sanitized = requireNotNull(FamilyInviteCodeSanitizer.sanitize(inviteCode)) { "validated above" }
        when (val result = familyApi.acceptInvite(sanitized, displayName)) {
            is ApiResult.Success -> _state.value = _state.value.copy(
                isAcceptingInvite = false,
                acceptedFamily = AcceptedFamilyUi(result.data.familyId, result.data.familyName, result.data.role),
            )
            is ApiResult.Failure -> _state.value = _state.value.copy(
                isAcceptingInvite = false,
                acceptInviteError = result.error.userMessage(),
            )
        }
    }

    /**
     * Review-round fix (specs/010-app-shell-and-screen-ux.md §5.2: "prefilled with the caller's
     * existing profile displayName when one exists"), **corrected in round 2**: the first cut of
     * this method called [DevicesApi.listDevices] unconditionally and trusted its first entry's
     * `ownerDisplayName`. 001 §4.2's guarantee is narrower than that: *"Open family: all members
     * see all devices... A **family-less caller** gets their **own devices only** (same response
     * shape; `ownerDisplayName` = their profile `displayName`)"* — the `ownerDisplayName ==
     * caller's-own-name` property holds **only** while the caller is family-less. A caller who
     * already has a family gets every member's devices back in an unspecified order, so
     * `firstOrNull()?.ownerDisplayName` could silently adopt a *different* family member's name
     * as "the caller's own" — reachable via a deep link into this screen with no Onboarding-typed
     * name and no prior check of the caller's family state, i.e. a PII-misattribution risk, not a
     * cosmetic one.
     *
     * The fix probes [FamilyApi.getMyFamily] first:
     * - **Success** (the caller has a family): the caller's own name comes straight from that
     *   response's own `members` list, matched by `me.userId` — never [DevicesApi.listDevices],
     *   which would return every member's devices for a family caller (001 §4.2).
     * - **A confirmed `FAMILY_NOT_FOUND` failure** (genuinely family-less): 001 §4.2's guarantee
     *   now holds, so [DevicesApi.listDevices]'s first entry's `ownerDisplayName` is safe to
     *   trust as the caller's own name.
     * - **Any other outcome** (an unresolved/ambiguous probe — `PROFILE_NOT_FOUND`, a transient
     *   failure, …): neither call site is trustworthy yet, so this leaves
     *   [AcceptInviteUiState.displayNameFallback] untouched (`null`) rather than guessing.
     *
     * Best-effort throughout: a caller with no devices yet, or any failed call, leaves
     * [AcceptInviteUiState.displayNameFallback] `null` — this is a convenience prefill, never a
     * blocker on the join flow (the screen's own display-name field still accepts manual entry
     * either way).
     */
    suspend fun loadDisplayNameFallback() {
        val fallback = when (val familyResult = familyApi.getMyFamily()) {
            is ApiResult.Success -> {
                val me = familyResult.data.me
                familyResult.data.members.firstOrNull { it.userId == me.userId }?.displayName
            }
            is ApiResult.Failure -> {
                if (familyResult.error is ApiError.FamilyNotFound) {
                    when (val devicesResult = devicesApi.listDevices()) {
                        is ApiResult.Success -> devicesResult.data.devices.firstOrNull()?.ownerDisplayName
                        is ApiResult.Failure -> null
                    }
                } else {
                    null
                }
            }
        }
        _state.value = _state.value.copy(displayNameFallback = fallback)
    }
}
