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
 */
class InvitesStateHolder(private val familyApi: FamilyApi) {

    private val _state = MutableStateFlow(InvitesUiState())
    val state: StateFlow<InvitesUiState> = _state.asStateFlow()

    /** §3.3 — parent only; the server enforces the role check (`403 AUTH_FORBIDDEN` for a
     * non-parent), surfaced here as an ordinary [InvitesUiState.createInviteError]. */
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
     * [InvitesUiState.acceptInviteError]. */
    suspend fun acceptInvite(inviteCode: String, displayName: String) {
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
