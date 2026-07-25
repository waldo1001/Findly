package com.findly.android.ui.groups

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupMemberLocationDto
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The group-map screen's pure state machine (001-api-contract.md §12.10). Constructor-injected
 * [CoroutineScope] — mirrors [com.findly.android.ui.map.MapStateHolder]'s exact shape
 * (specs/003-android-client.md §12.2: "`GroupMapStateHolder` polls ... the same way
 * `MapStateHolder` treats the family map") — an eager `init` load plus a public [refresh] for
 * pull-to-refresh, not a real timer-driven poll loop (family map doesn't have one either).
 */
class GroupMapStateHolder(
    private val groupId: String,
    private val groupsApi: GroupsApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<GroupMapUiState>(GroupMapUiState.Loading)
    val state: StateFlow<GroupMapUiState> = _state.asStateFlow()

    init {
        scope.launch { refresh() }
    }

    suspend fun refresh() {
        val current = _state.value
        if (current is GroupMapUiState.Content) {
            _state.value = current.copy(isRefreshing = true)
        }
        when (val result = groupsApi.getGroupLatestLocations(groupId)) {
            is ApiResult.Success -> _state.value = GroupMapUiState.Content(result.data.members.map { it.toUi() })
            is ApiResult.Failure -> _state.value = result.error.toMapState()
        }
    }
}

private fun GroupMemberLocationDto.toUi(): GroupMapMemberUi = GroupMapMemberUi(
    userId = userId,
    displayName = displayName,
    role = role,
    lat = location?.lat,
    lon = location?.lon,
    accuracyM = location?.accuracyM,
    recordedAt = location?.recordedAt,
    isStale = location?.isStale,
)

private fun ApiError.toMapState(): GroupMapUiState =
    if (this is ApiError.GroupExpired) GroupMapUiState.Expired() else GroupMapUiState.Error(userMessage())
