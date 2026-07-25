package com.findly.android.ui.groups

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The join-group screen's pure state machine (001-api-contract.md §12.6). No constructor
 * [kotlinx.coroutines.CoroutineScope] is needed — same shape as
 * [com.findly.android.ui.groups.CreateGroupStateHolder] — a user-initiated form only.
 *
 * Every [join] call runs [code] through [GroupJoinCodeSanitizer] **before** touching the network
 * — this is the one call site every code reaches, whether typed by hand on
 * [GroupJoinScreen] or prefilled from the `findly://group-join?code=…` deep link (an untrusted
 * external input, specs/003-android-client.md §12.2); an unparsable code never leaves the device.
 */
class GroupJoinStateHolder(
    private val groupsApi: GroupsApi,
    private val needsDisplayName: Boolean,
) {
    private val _state = MutableStateFlow(GroupJoinUiState())
    val state: StateFlow<GroupJoinUiState> = _state.asStateFlow()

    fun validate(code: String, displayName: String?): String? = when {
        GroupJoinCodeSanitizer.sanitize(code) == null -> "Enter a valid 8-character group code"
        needsDisplayName && displayName.isNullOrBlank() -> "Enter a display name"
        else -> null
    }

    suspend fun join(code: String, displayName: String?) {
        val problem = validate(code, displayName)
        if (problem != null) {
            _state.value = _state.value.copy(validationError = problem)
            return
        }

        _state.value = _state.value.copy(isJoining = true, validationError = null, joinError = null)
        val sanitized = requireNotNull(GroupJoinCodeSanitizer.sanitize(code)) { "validated above" }
        when (val result = groupsApi.joinGroup(sanitized, displayName)) {
            is ApiResult.Success -> _state.value = _state.value.copy(isJoining = false, joined = result.data.toUi())
            is ApiResult.Failure -> _state.value = _state.value.copy(isJoining = false, joinError = result.error.userMessage())
        }
    }
}

private fun GroupDto.toUi(): GroupSummaryUi = GroupSummaryUi(
    groupId = groupId,
    name = name,
    endsAt = endsAt,
    expiryPolicy = expiryPolicy,
    state = state,
    role = role,
    memberCount = memberCount,
    code = code,
)
