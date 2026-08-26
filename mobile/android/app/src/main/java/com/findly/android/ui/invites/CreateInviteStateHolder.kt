package com.findly.android.ui.invites

import com.findly.android.network.ApiResult
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The create-invite screen's pure state machine (001-api-contract.md §3.3, specs/010-app-shell-
 * and-screen-ux.md §5.1). Split out of the retired combined `InvitesStateHolder` (010 §6) — this
 * is the parent-only "create an invite" half; [AcceptInviteStateHolder] is the other.
 *
 * **specs/010-app-shell-and-screen-ux.md §2.1 note (carried over from the retired
 * `InvitesStateHolder`):** `createInvite` is a `POST` — a mutation by HTTP semantics and by §2.1's
 * own example — and §2.1's routing rule is a MUST scoped to *load* paths only ("Mutation/action
 * failures… keep their existing inline error rendering — this rule is about the load path"). A
 * confirmed `PROFILE_NOT_FOUND`/`FAMILY_NOT_FOUND` here therefore renders inline via
 * [CreateInviteUiState.createInviteError], the same as every other mutation on this client (this
 * screen is reachable only via the parent-gated drawer item, so a caller without a profile/family
 * here is already a near-unreachable edge case).
 */
class CreateInviteStateHolder(private val familyApi: FamilyApi) {

    private val _state = MutableStateFlow(CreateInviteUiState())
    val state: StateFlow<CreateInviteUiState> = _state.asStateFlow()

    /** §3.3 — parent only; the server enforces the role check (`403 AUTH_FORBIDDEN` for a
     * non-parent), surfaced here as an ordinary [CreateInviteUiState.createInviteError]. */
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

    /** specs/010-app-shell-and-screen-ux.md §5.1 bullet 6 — "Create another" resets the form
     * without leaving the screen, clearing both the previous invite and any stale error. */
    fun reset() {
        _state.value = CreateInviteUiState()
    }
}
