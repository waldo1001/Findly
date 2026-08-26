package com.findly.android.ui.invites

import com.findly.android.network.ApiResult
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The invites screen's pure state machine (001-api-contract.md §3.3/§3.4). No constructor
 * [kotlinx.coroutines.CoroutineScope] is needed (like [com.findly.android.ui.history.HistoryStateHolder])
 * since there is nothing to eagerly load — both actions are user-initiated forms.
 * [InvitesViewModel] launches [createInvite]/[acceptInvite] on its own `viewModelScope`.
 */
class InvitesStateHolder(private val familyApi: FamilyApi) {

    private val _state = MutableStateFlow(InvitesUiState())
    val state: StateFlow<InvitesUiState> = _state.asStateFlow()

    /** §3.3 — parent only; the server enforces the role check (`403 AUTH_FORBIDDEN` for a
     * non-parent), surfaced here as an ordinary [InvitesUiState.createInviteError]. */
    suspend fun createInvite(role: String, emailHint: String? = null) {
        _state.value = _state.value.copy(isCreatingInvite = true, createInviteError = null, createInviteRouteToOnboarding = null)
        when (val result = familyApi.createInvite(role, emailHint)) {
            is ApiResult.Success -> _state.value = _state.value.copy(
                isCreatingInvite = false,
                createdInvite = CreatedInviteUi(result.data.inviteCode, result.data.role, result.data.expiresAt),
            )
            is ApiResult.Failure -> {
                // specs/010-app-shell-and-screen-ux.md §2.1: POST /families/me/invites is
                // parent-only, family-scoped (001 §3.3/§1.6) — this screen has no separate eager
                // load, so createInvite is its load path for this rule's purposes.
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = true)
                _state.value = if (variant != null) {
                    _state.value.copy(isCreatingInvite = false, createInviteRouteToOnboarding = variant)
                } else {
                    _state.value.copy(isCreatingInvite = false, createInviteError = result.error.userMessage())
                }
            }
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
