package com.findly.android.ui.map

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LatestDeviceDto
import com.findly.android.network.dto.LatestMemberDto
import com.findly.android.network.ports.LocationsApi
import com.findly.android.network.userMessage
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
                _state.value = MapUiState.Content(result.data.members.map { it.toUi() })
            }
            is ApiResult.Failure -> {
                _state.value = MapUiState.Error(result.error.userMessage())
            }
        }
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
