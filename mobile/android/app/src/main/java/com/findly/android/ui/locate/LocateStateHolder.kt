package com.findly.android.ui.locate

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.LastKnownDto
import com.findly.android.network.dto.LocateFixDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.ports.LocateApi
import com.findly.android.network.userMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private val TERMINAL_STATUSES = setOf("fulfilled", "expired", "pushFailed")

/**
 * The "locate now" screen's pure state machine (001-api-contract.md §6). Constructor-injected
 * [CoroutineScope] (tests supply `backgroundScope`, same pattern as
 * [com.findly.android.ui.home.HomeStateHolder]) — its cancellation (e.g. `viewModelScope`
 * clearing) stops any in-flight poll loop automatically, nothing extra to clean up.
 * [pollIntervalMillis] defaults to the spec's 2 s (§6.2: "Clients SHOULD poll every 2 s until
 * terminal") but is overridable so tests don't need to wait on real wall-clock time — combined
 * with `kotlinx.coroutines.test`'s virtual time, [kotlinx.coroutines.delay] inside the poll loop
 * advances instantly under `runTest`.
 */
class LocateStateHolder(
    private val locateApi: LocateApi,
    private val scope: CoroutineScope,
    private val pollIntervalMillis: Long = 2000L,
) {
    private val _state = MutableStateFlow<LocateUiState>(LocateUiState.Idle)
    val state: StateFlow<LocateUiState> = _state.asStateFlow()

    private var pollJob: Job? = null

    /** Exactly one of [targetUserId]/[targetDeviceId] (§6.1) — validated by
     * [com.findly.android.network.dto.CreateLocateRequestRequestDto.requireExactlyOneTarget]
     * inside the client, not re-validated here. Cancels any prior in-flight poll for this holder
     * before starting a new request. */
    fun requestLocate(targetUserId: String? = null, targetDeviceId: String? = null) {
        pollJob?.cancel()
        pollJob = scope.launch {
            when (val result = locateApi.createLocateRequest(targetUserId, targetDeviceId)) {
                is ApiResult.Success -> onCreated(result.data)
                is ApiResult.Failure -> _state.value = LocateUiState.Error(result.error.userMessage())
            }
        }
    }

    /** Cancels an in-flight poll loop (e.g. the user navigates away). */
    fun cancelPolling() {
        pollJob?.cancel()
    }

    private suspend fun onCreated(dto: LocateRequestDto) {
        if (dto.status in TERMINAL_STATUSES) {
            _state.value = LocateUiState.Terminal(dto.requestId, dto.status, fix = null, lastKnown = dto.lastKnown?.toUi())
            return
        }
        _state.value = LocateUiState.Polling(dto.requestId, dto.lastKnown?.toUi(), dto.expiresAt)
        pollUntilTerminal(dto.requestId)
    }

    private suspend fun pollUntilTerminal(requestId: String) {
        while (true) {
            delay(pollIntervalMillis)
            when (val result = locateApi.getLocateRequest(requestId)) {
                is ApiResult.Success -> {
                    val dto = result.data
                    if (dto.status in TERMINAL_STATUSES) {
                        val lastKnown = (_state.value as? LocateUiState.Polling)?.lastKnown
                        _state.value = LocateUiState.Terminal(dto.requestId, dto.status, dto.fix?.toUi(), lastKnown)
                        return
                    }
                    val previous = _state.value as? LocateUiState.Polling
                    _state.value = LocateUiState.Polling(dto.requestId, previous?.lastKnown, dto.expiresAt)
                }
                is ApiResult.Failure -> {
                    _state.value = LocateUiState.Error(result.error.userMessage())
                    return
                }
            }
        }
    }
}

private fun LastKnownDto.toUi(): LastKnownUi = LastKnownUi(deviceId, lat, lon, accuracyM, recordedAt)

private fun LocateFixDto.toUi(): LocateFixUi = LocateFixUi(deviceId, lat, lon, accuracyM, recordedAt, batteryPct)
