package com.findly.android.ui.groups

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupDetailDto
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.dto.GroupMemberDto
import com.findly.android.network.dto.UpdateGroupRequestDto
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val NOT_OWNER_MESSAGE = "Only the group owner can do that."
private const val OWNER_CANNOT_LEAVE_MESSAGE = "As the group owner, you can't leave — end or delete the group instead."

/**
 * The group-detail screen's pure state machine (001-api-contract.md §12.3-§12.5, §12.7-§12.9).
 * Constructor-injected [CoroutineScope] — same pattern as
 * [com.findly.android.ui.map.MapStateHolder]. Owner-only mutations (rename, extend/end,
 * rotate, kick, delete) are gated by [GroupDetailUiState.Content.isOwner] **client-side before any
 * network call**, mirroring [com.findly.android.ui.settings.SettingsStateHolder]'s
 * `isParent`-gated convention — the server enforces the same role checks regardless (403
 * `AUTH_FORBIDDEN` for role violations elsewhere in 001, though group ownership violations here
 * are actually unreachable server-side misuse given the client gate; defense in depth, not the
 * only guard).
 */
class GroupDetailStateHolder(
    private val groupId: String,
    private val groupsApi: GroupsApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<GroupDetailUiState>(GroupDetailUiState.Loading)
    val state: StateFlow<GroupDetailUiState> = _state.asStateFlow()

    init {
        scope.launch { load() }
    }

    suspend fun load() {
        _state.value = GroupDetailUiState.Loading
        when (val result = groupsApi.getGroup(groupId)) {
            is ApiResult.Success -> _state.value = result.data.toUi()
            is ApiResult.Failure -> _state.value = result.error.toDetailState()
        }
    }

    /** §12.4 — owner-only; name only. */
    suspend fun rename(name: String) = mutateGroup { groupsApi.updateGroup(groupId, UpdateGroupRequestDto(name = name)) }

    /** §12.4 — owner-only; `endsAt` only. Extending a `grace`-state group reactivates it (005
     * §2.2); as a convenience, `endsAt ≤ now + 5 min` ends the group now (both server-side rules,
     * nothing special needed here). */
    suspend fun updateEndsAt(endsAtIso: String) =
        mutateGroup { groupsApi.updateGroup(groupId, UpdateGroupRequestDto(endsAt = endsAtIso)) }

    private suspend fun mutateGroup(call: suspend () -> ApiResult<GroupDto>) {
        val current = _state.value as? GroupDetailUiState.Content ?: return
        if (!current.isOwner) {
            _state.value = current.copy(mutationError = NOT_OWNER_MESSAGE)
            return
        }
        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = call()) {
            is ApiResult.Success -> _state.value = current.copy(
                name = result.data.name,
                endsAt = result.data.endsAt,
                state = result.data.state,
                memberCount = result.data.memberCount,
                code = result.data.code,
                isMutating = false,
            )
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §12.7 — owner-only. The old code stops working instantly. */
    suspend fun rotateCode() {
        val current = _state.value as? GroupDetailUiState.Content ?: return
        if (!current.isOwner) {
            _state.value = current.copy(mutationError = NOT_OWNER_MESSAGE)
            return
        }
        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = groupsApi.rotateGroupCode(groupId)) {
            is ApiResult.Success -> _state.value = current.copy(code = result.data.code, isMutating = false)
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §12.9 — owner-only, bare 204; the target's position disappears from the group map
     * immediately (server-side — this just mirrors the roster removal locally). */
    suspend fun kickMember(userId: String) {
        val current = _state.value as? GroupDetailUiState.Content ?: return
        if (!current.isOwner) {
            _state.value = current.copy(mutationError = NOT_OWNER_MESSAGE)
            return
        }
        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = groupsApi.removeGroupMember(groupId, userId)) {
            is ApiResult.Success -> _state.value = current.copy(
                members = current.members?.filterNot { it.userId == userId },
                memberCount = (current.memberCount - 1).coerceAtLeast(0),
                isMutating = false,
            )
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §12.5 — owner-only, bare 204. Immediate, synchronous hard delete (005 §2.4) in any state,
     * regardless of policy. */
    suspend fun deleteGroup() {
        val current = _state.value as? GroupDetailUiState.Content ?: return
        if (!current.isOwner) {
            _state.value = current.copy(mutationError = NOT_OWNER_MESSAGE)
            return
        }
        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = groupsApi.deleteGroup(groupId)) {
            is ApiResult.Success -> _state.value = current.copy(isMutating = false, left = true)
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §12.8 — bare 204, any non-owner member. The owner cannot leave (`ownerCannotLeave`, §12.8)
     * — gated client-side too, matching every other owner/parent-only action's convention, even
     * though the server enforces this as a `VALIDATION_FAILED` rather than a role check. */
    suspend fun leaveGroup() {
        val current = _state.value as? GroupDetailUiState.Content ?: return
        if (current.isOwner) {
            _state.value = current.copy(mutationError = OWNER_CANNOT_LEAVE_MESSAGE)
            return
        }
        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = groupsApi.leaveGroup(groupId)) {
            is ApiResult.Success -> _state.value = current.copy(isMutating = false, left = true)
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }
}

private fun GroupDetailDto.toUi(): GroupDetailUiState.Content = GroupDetailUiState.Content(
    groupId = groupId,
    name = name,
    endsAt = endsAt,
    expiryPolicy = expiryPolicy,
    state = state,
    role = role,
    memberCount = memberCount,
    code = code,
    createdAt = createdAt,
    members = members?.map { it.toUi() },
)

private fun GroupMemberDto.toUi(): GroupMemberUi = GroupMemberUi(
    userId = userId,
    displayName = displayName,
    role = role,
    joinedAt = joinedAt,
)

private fun ApiError.toDetailState(): GroupDetailUiState =
    if (this is ApiError.GroupExpired) GroupDetailUiState.Expired() else GroupDetailUiState.Error(userMessage())
