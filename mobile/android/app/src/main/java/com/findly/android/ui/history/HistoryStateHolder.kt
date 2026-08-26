package com.findly.android.ui.history

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.HistoryPointDto
import com.findly.android.network.dto.LocationHistoryResponseDto
import com.findly.android.network.ports.LocationsApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The history screen's pure state machine (001-api-contract.md §5.3). No constructor
 * [kotlinx.coroutines.CoroutineScope] is needed (unlike [com.findly.android.ui.home.HomeStateHolder]/
 * [com.findly.android.ui.map.MapStateHolder]) since there is nothing to eagerly load — a
 * query needs a date range/userId from the UI first. [HistoryViewModel] launches [load]/[loadMore]
 * on its own `viewModelScope`.
 */
class HistoryStateHolder(private val locationsApi: LocationsApi) {

    private val _state = MutableStateFlow<HistoryUiState>(HistoryUiState.Idle)
    val state: StateFlow<HistoryUiState> = _state.asStateFlow()

    private var lastQuery: Query? = null

    private data class Query(val userId: String, val from: String, val to: String, val deviceId: String?)

    /** Runs a fresh date-range query (§5.3 — `from`/`to` inclusive `YYYY-MM-DD`, max 31-day span,
     * enforced server-side), replacing any existing results. */
    suspend fun load(userId: String, from: String, to: String, deviceId: String? = null) {
        lastQuery = Query(userId, from, to, deviceId)
        _state.value = HistoryUiState.Loading
        val result = locationsApi.getLocationHistory(userId = userId, from = from, to = to, deviceId = deviceId)
        applyResult(result, existing = emptyList())
    }

    /** Cursor pagination (§5.3's opaque `nextCursor`) — appends the next page to the existing
     * list. A no-op if there's no `nextCursor` or [load] hasn't run yet, so a screen can call this
     * unconditionally from a "load more" action without checking state first. */
    suspend fun loadMore() {
        val query = lastQuery ?: return
        val current = _state.value
        if (current !is HistoryUiState.Content || current.nextCursor == null) return

        _state.value = current.copy(isLoadingMore = true)
        val result = locationsApi.getLocationHistory(
            userId = query.userId,
            from = query.from,
            to = query.to,
            deviceId = query.deviceId,
            cursor = current.nextCursor,
        )
        applyResult(result, existing = current.points)
    }

    private fun applyResult(result: ApiResult<LocationHistoryResponseDto>, existing: List<HistoryPointUi>) {
        _state.value = when (result) {
            is ApiResult.Success -> HistoryUiState.Content(
                points = existing + result.data.points.map { it.toUi() },
                nextCursor = result.data.nextCursor,
            )
            is ApiResult.Failure -> {
                // specs/010-app-shell-and-screen-ux.md §2.1: GET /locations/history is
                // family-scoped (001 §1.6 — "member").
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = true)
                if (variant != null) HistoryUiState.RouteToOnboarding(variant) else HistoryUiState.Error(result.error.userMessage())
            }
        }
    }
}

private fun HistoryPointDto.toUi(): HistoryPointUi = HistoryPointUi(
    deviceId = deviceId,
    recordedAt = recordedAt,
    lat = lat,
    lon = lon,
    accuracyM = accuracyM,
    batteryPct = batteryPct,
    source = source,
)
