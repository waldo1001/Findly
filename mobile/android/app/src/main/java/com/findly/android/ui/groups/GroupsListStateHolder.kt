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
 * [CoroutineScope] — same pattern as [com.findly.android.ui.map.MapStateHolder]. Loads
 * `GET /groups` and, alongside it, probes `GET /families/me` (001 §1.5.4) purely to classify the
 * caller for the family-less-home behavior (specs/003-android-client.md §12.2) — this screen is
 * the one place in the app that must work identically whether the caller has a family or not.
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

    /** Re-fetches both the group list and the family-probe. Public so pull-to-refresh / retry can
     * call it directly, mirroring [com.findly.android.ui.map.MapStateHolder.refresh]. */
    suspend fun refresh() {
        val current = _state.value
        if (current is GroupsListUiState.Content) {
            _state.value = current.copy(isRefreshing = true)
        }

        when (val result = groupsApi.listGroups()) {
            is ApiResult.Failure -> _state.value = GroupsListUiState.Error(result.error.userMessage())
            is ApiResult.Success -> {
                val (hasFamily, needsDisplayName) = resolveProfileStatus()
                _state.value = GroupsListUiState.Content(
                    groups = result.data.groups.map { it.toUi() },
                    limits = result.features?.limits,
                    hasFamily = hasFamily,
                    needsDisplayName = needsDisplayName,
                )
            }
        }
    }

    /** Returns `(hasFamily, needsDisplayName)`. `PROFILE_NOT_FOUND` means the caller has no
     * profile at all (`needsDisplayName = true`, 001 §12.1/§12.6's bootstrap rule);
     * `FAMILY_NOT_FOUND` means a profile exists but no family; any other failure (network, etc.)
     * is unrelated to family status and must not mislabel the caller as family-less. */
    private suspend fun resolveProfileStatus(): Pair<Boolean, Boolean> = when (val result = familyApi.getMyFamily()) {
        is ApiResult.Success -> true to false
        is ApiResult.Failure -> when (result.error) {
            is ApiError.ProfileNotFound -> false to true
            is ApiError.FamilyNotFound -> false to false
            else -> true to false
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
