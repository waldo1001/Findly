package com.findly.android.ui.family

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.MemberDto
import com.findly.android.network.dto.UpdateMemberRequestDto
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val NOT_PARENT_MESSAGE = "Only a parent can do this"

/**
 * The Family screen's pure state machine (specs/010-app-shell-and-screen-ux.md §4.1's `Family`
 * route, extracted from the retired `SettingsStateHolder`'s family/member half — devices moved to
 * [com.findly.android.ui.devices.DevicesStateHolder]; wire shapes specs/001-api-contract.md
 * §3.2/§3.5/§3.6). Constructor-injected [CoroutineScope] — same pattern as
 * [com.findly.android.ui.devices.DevicesStateHolder]. Every mutation is gated by [isParent]
 * client-side before any network call — the server enforces the same role checks regardless
 * (defense in depth, not the only guard).
 */
class FamilyMembersStateHolder(
    private val familyApi: FamilyApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<FamilyMembersUiState>(FamilyMembersUiState.Loading)
    val state: StateFlow<FamilyMembersUiState> = _state.asStateFlow()

    init {
        scope.launch { load() }
    }

    val isParent: Boolean get() = (_state.value as? FamilyMembersUiState.Content)?.myRole == "parent"

    suspend fun load() {
        _state.value = FamilyMembersUiState.Loading
        when (val result = familyApi.getMyFamily()) {
            is ApiResult.Failure -> {
                // `GET /families/me` is family-scoped (001 §1.5.4/§3.2).
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = true)
                _state.value = if (variant != null) {
                    FamilyMembersUiState.RouteToOnboarding(variant)
                } else {
                    FamilyMembersUiState.Error(result.error.userMessage())
                }
            }
            is ApiResult.Success -> {
                _state.value = FamilyMembersUiState.Content(
                    familyName = result.data.familyName,
                    myRole = result.data.me.role,
                    members = result.data.members.map { it.toUi() },
                )
            }
        }
    }

    /** §3.5 — role/displayName; parent-only. */
    suspend fun updateMember(userId: String, role: String? = null, displayName: String? = null) {
        val current = _state.value as? FamilyMembersUiState.Content ?: return
        if (current.myRole != "parent") {
            _state.value = current.copy(mutationError = NOT_PARENT_MESSAGE)
            return
        }

        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = familyApi.updateMember(userId, UpdateMemberRequestDto(role, displayName))) {
            is ApiResult.Success -> {
                val updated = current.members.map { member -> if (member.userId == userId) result.data.toUi() else member }
                _state.value = current.copy(members = updated, isMutating = false)
            }
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §3.6 — bare 204; parent-only. The server rejects the last-parent removing themselves
     * (`lastParent`) — surfaced here as an ordinary [FamilyMembersUiState.Content.mutationError],
     * not special-cased. */
    suspend fun removeMember(userId: String) {
        val current = _state.value as? FamilyMembersUiState.Content ?: return
        if (current.myRole != "parent") {
            _state.value = current.copy(mutationError = NOT_PARENT_MESSAGE)
            return
        }

        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = familyApi.removeMember(userId)) {
            is ApiResult.Success -> _state.value = current.copy(
                members = current.members.filterNot { it.userId == userId },
                isMutating = false,
            )
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }
}

private fun MemberDto.toUi(): MemberUi = MemberUi(userId, role, displayName, joinedAt)
