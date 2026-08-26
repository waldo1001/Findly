package com.findly.android.ui.invites

import com.findly.android.network.ApiResult
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The invites screen's pure state machine (001-api-contract.md §3.3/§3.4). No constructor
 * [kotlinx.coroutines.CoroutineScope] is needed (like [com.findly.android.ui.history.HistoryStateHolder])
 * since there is nothing to eagerly load — both actions are user-initiated forms.
 * [InvitesViewModel] launches [createInvite]/[acceptInvite] on its own `viewModelScope`.
 *
 * **specs/010-app-shell-and-screen-ux.md §2.1 note (review finding, reverted 2026-08-26):**
 * `createInvite` is a `POST` — a mutation by HTTP semantics and by §2.1's own example — and §2.1's
 * routing rule is a MUST scoped to *load* paths only ("Mutation/action failures… keep their
 * existing inline error rendering — this rule is about the load path"). An earlier revision routed
 * a confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` here through `ProfileDeadEndRouting` on the
 * reasoning that this screen has no separate eager load, so `createInvite` stands in for one; that
 * redraws the spec's GET-vs-POST bright line rather than following it, so it's reverted to the
 * inline [InvitesUiState.createInviteError] every other mutation on this client uses. (This screen
 * is reachable only via the parent-gated drawer item, so a caller without a profile/family here is
 * already a near-unreachable edge case.) Whether §2.1 should extend to "any endpoint with no
 * separate eager load" is tracked as a spec follow-up, not pre-empted here.
 */
class InvitesStateHolder(private val familyApi: FamilyApi) {

    private val _state = MutableStateFlow(InvitesUiState())
    val state: StateFlow<InvitesUiState> = _state.asStateFlow()

    /** §3.3 — parent only; the server enforces the role check (`403 AUTH_FORBIDDEN` for a
     * non-parent), surfaced here as an ordinary [InvitesUiState.createInviteError] — a mutation,
     * so `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` render inline here too (see this class's doc). */
    suspend fun createInvite(role: String, emailHint: String? = null) {
        _state.value = _state.value.copy(isCreatingInvite = true, createInviteError = null)
        when (val result = familyApi.createInvite(role, emailHint)) {
            is ApiResult.Success -> _state.value = _state.value.copy(
                isCreatingInvite = false,
                createdInvite = CreatedInviteUi(result.data.inviteCode, result.data.role, result.data.expiresAt),
            )
            is ApiResult.Failure -> _state.value = _state.value.copy(
                isCreatingInvite = false,
                createInviteError = result.error.userMessage(),
            )
        }
    }

    /** §3.4 — caller MUST NOT already belong to a family; `INVITE_INVALID`/`INVITE_ALREADY_USED`/
     * `INVITE_EXPIRED`/`FAMILY_ALREADY_MEMBER` all surface as an ordinary
     * [InvitesUiState.acceptInviteError]. `displayName` is required unconditionally server-side
     * (`backend/src/http/validate.ts`, unlike §12.1/§12.6's create/join-group where it's only
     * required when the caller has no profile yet) — a blank value never reaches the network,
     * mirroring [com.findly.android.ui.family.CreateFamilyStateHolder.validate]'s same
     * unconditional "gate before any network call" convention (A21 review — this is one of the
     * four equally-weighted first-run bootstrap paths off Onboarding's profile-less variant,
     * specs/010-app-shell-and-screen-ux.md §2.2, the retired `GroupsListUiState.ProfileNeeded`'s
     * replacement). */
    suspend fun acceptInvite(inviteCode: String, displayName: String) {
        if (displayName.isBlank()) {
            _state.value = _state.value.copy(acceptInviteError = "Enter a display name")
            return
        }

        _state.value = _state.value.copy(isAcceptingInvite = true, acceptInviteError = null)
        when (val result = familyApi.acceptInvite(inviteCode, displayName)) {
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
}
