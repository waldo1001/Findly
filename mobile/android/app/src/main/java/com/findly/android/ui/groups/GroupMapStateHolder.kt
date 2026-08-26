package com.findly.android.ui.groups

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.dto.GroupMemberLocationDto
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.userMessage
import com.findly.android.ui.map.CameraCommand
import com.findly.android.ui.map.CameraPolicyState
import com.findly.android.ui.map.MapCamera
import com.findly.android.ui.map.MapCameraPolicy
import com.findly.android.ui.map.MapCameraTarget
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

    // specs/010-app-shell-and-screen-ux.md §3.2/§3.4: the same camera policy state the family map
    // keeps, through the same renderer seam.
    private var cameraPolicyState = CameraPolicyState.INITIAL
    private var cameraSeq = 0L

    init {
        scope.launch { refresh() }
    }

    suspend fun refresh() {
        val current = _state.value
        if (current is GroupMapUiState.Content) {
            _state.value = current.copy(isRefreshing = true)
        }
        when (val result = groupsApi.getGroupLatestLocations(groupId)) {
            is ApiResult.Success -> {
                val members = result.data.members.map { it.toUi() }
                // RED-before-GREEN placeholder (devloop/A34): never mints a camera command yet.
                _state.value = GroupMapUiState.Content(members = members)
            }
            is ApiResult.Failure -> _state.value = result.error.toMapState()
        }
    }

    /** specs/010 §3.5, position-only mirror of [com.findly.android.ui.map.MapStateHolder.selectMember]. */
    fun selectMember(userId: String) {
        val current = _state.value as? GroupMapUiState.Content ?: return
        _state.value = current.copy(selectedUserId = userId)
    }

    /** specs/010 §3.4's explicit fit-all action. */
    fun fitAll() {
        // TODO
    }

    private fun nextCameraCommand(target: MapCameraTarget): CameraCommand {
        cameraSeq += 1
        return CameraCommand(cameraSeq, target)
    }
}

private fun List<GroupMapMemberUi>.locatedPoints(): List<Pair<Double, Double>> =
    filter { it.hasLocation }.map { it.lat!! to it.lon!! }

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
