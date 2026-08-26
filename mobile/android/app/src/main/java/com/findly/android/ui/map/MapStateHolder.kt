package com.findly.android.ui.map

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestMemberDto
import com.findly.android.network.ports.LocationsApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The live-map screen's pure state machine (001-api-contract.md §5.2). Constructor-injected
 * [CoroutineScope] so tests supply a `TestScope`/`backgroundScope` — mirrors [HomeStateHolder]'s
 * pattern (specs/003-android-client.md §12/§14). [MapViewModel] is the thin `ViewModel` wrapper.
 */
class MapStateHolder(
    private val locationsApi: LocationsApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<MapUiState>(MapUiState.Loading)
    val state: StateFlow<MapUiState> = _state.asStateFlow()

    // specs/010-app-shell-and-screen-ux.md §3.4: WHEN the camera re-runs, tracked as pure state
    // across this holder's lifetime (see MapCameraPolicy's doc) — never on an ordinary refresh,
    // except the one carve-out the spec grants (a zero-point open's first-ever point arrival).
    private var cameraPolicyState = CameraPolicyState.INITIAL
    private var cameraSeq = 0L

    init {
        scope.launch { refresh() }
    }

    /** Re-fetches the whole family roster (§5.2 — one call, one partition scan server-side).
     * Public so the screen's pull-to-refresh / retry action can call it directly. */
    suspend fun refresh() {
        val current = _state.value
        if (current is MapUiState.Content) {
            _state.value = current.copy(isRefreshing = true)
        }
        when (val result = locationsApi.getLatestLocations()) {
            is ApiResult.Success -> {
                val members = result.data.members.map { it.toUi() }
                // RED-before-GREEN placeholder (devloop/A34): never mints a camera command yet.
                val previousCommand = (current as? MapUiState.Content)?.cameraCommand
                val previousSelected = (current as? MapUiState.Content)?.selectedUserId
                    ?.takeIf { id -> members.any { it.userId == id } }
                _state.value = MapUiState.Content(
                    members = members,
                    selectedUserId = previousSelected,
                    cameraCommand = previousCommand,
                )
            }
            is ApiResult.Failure -> {
                // specs/010-app-shell-and-screen-ux.md §2.1: GET /locations/latest is family-scoped
                // (001 §1.6 — "member") — a confirmed PROFILE_NOT_FOUND/FAMILY_NOT_FOUND routes to
                // Onboarding instead of the dead-end retryable card.
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = true)
                _state.value = if (variant != null) {
                    MapUiState.RouteToOnboarding(variant)
                } else {
                    MapUiState.Error(result.error.userMessage())
                }
            }
        }
    }

    /** specs/010 §3.5: selects/deselects [userId], zooming to their freshest located device at
     * [MapCamera.SINGLE_POINT_ZOOM] when one exists; a member with no located device can still be
     * selected (row/marker highlight) but the camera MUST NOT move. Tapping the already-selected
     * member deselects. RED-before-GREEN placeholder: always selects, never moves the camera. */
    fun selectMember(userId: String) {
        val current = _state.value as? MapUiState.Content ?: return
        _state.value = current.copy(selectedUserId = userId)
    }

    /** specs/010 §3.4's explicit fit-all action: re-runs [MapCamera.target] over the currently
     * loaded points unconditionally. RED-before-GREEN placeholder: no-op. */
    fun fitAll() {
        // TODO
    }
}

private fun LatestMemberDto.toUi(): RosterMemberUi = RosterMemberUi(
    userId = userId,
    displayName = displayName,
    devices = devices.map { it.toUi() },
)

private fun LatestDeviceDto.toUi(): RosterDeviceUi = RosterDeviceUi(
    deviceId = deviceId,
    deviceName = deviceName,
    lat = lat,
    lon = lon,
    recordedAt = recordedAt,
    batteryPct = batteryPct,
    trackingEnabled = trackingEnabled,
    syncIntervalMinutes = syncIntervalMinutes,
    isStale = isStale,
)
