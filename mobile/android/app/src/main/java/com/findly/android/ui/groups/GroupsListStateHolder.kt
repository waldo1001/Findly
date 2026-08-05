package com.findly.android.ui.groups

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The groups list screen's pure state machine (001-api-contract.md §12.2). Constructor-injected
 * [CoroutineScope] — same pattern as [com.findly.android.ui.map.MapStateHolder]. Probes
 * `GET /families/me` (001 §1.5.4) **first**, purely to classify the caller — only once that
 * probe rules out "no profile at all" does it call `GET /groups`, since that call needs a profile
 * (§12.2) and would otherwise 404 for a profile-less caller (specs/003-android-client.md §12.2;
 * A21). This screen is the one place in the app that must work identically whether the caller has
 * a family, has a profile but no family, or has no profile at all.
 */
class GroupsListStateHolder(
    private val groupsApi: GroupsApi,
    private val familyApi: FamilyApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<GroupsListUiState>(GroupsListUiState.Loading)
    val state: StateFlow<GroupsListUiState> = _state.asStateFlow()

    init {
        scope.launch { refresh() }
    }

    /** Re-fetches the family-probe and, unless the caller is profile-less, the group list.
     * Public so pull-to-refresh / retry can call it directly, mirroring
     * [com.findly.android.ui.map.MapStateHolder.refresh]. */
    suspend fun refresh() {
        val current = _state.value
        if (current is GroupsListUiState.Content) {
            _state.value = current.copy(isRefreshing = true)
        }

        val profileResult = familyApi.getMyFamily()
        if (profileResult is ApiResult.Failure && profileResult.error is ApiError.ProfileNotFound) {
            // 001 §1.5.3/§12.2: no profile at all — GET /groups would 404 too, so never attempt
            // it. This is the fix for the A21 bug: the old code called listGroups() unconditionally
            // and only classified the caller afterwards, stranding a profile-less user on
            // GroupsListUiState.Error instead of the four bootstrap paths.
            _state.value = GroupsListUiState.ProfileNeeded
            return
        }

        when (val result = groupsApi.listGroups()) {
            is ApiResult.Failure -> _state.value = GroupsListUiState.Error(result.error.userMessage())
            is ApiResult.Success -> {
                _state.value = GroupsListUiState.Content(
                    groups = result.data.groups.map { it.toUi() },
                    limits = result.features?.limits,
                    // FAMILY_NOT_FOUND (profile exists, no family) -> false; any other outcome —
                    // a genuine Success, or an unrelated failure (network, etc.) — defaults to
                    // true, since only a confirmed FAMILY_NOT_FOUND is evidence the caller is
                    // actually family-less (never mislabel on an inconclusive probe).
                    hasFamily = !(profileResult is ApiResult.Failure && profileResult.error is ApiError.FamilyNotFound),
                )
            }
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
