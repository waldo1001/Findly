package com.findly.android.ui.devices

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.UpdateDeviceRequestDto
import com.findly.android.network.ports.DevicesApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val NOT_PARENT_MESSAGE = "Only a parent can do this"

/**
 * The Devices screen's pure state machine (specs/010-app-shell-and-screen-ux.md §4; wire shapes
 * specs/001-api-contract.md §4.2/§4.3). Constructor-injected [CoroutineScope] — same pattern as
 * the retired `SettingsStateHolder`/[com.findly.android.ui.map.MapStateHolder].
 *
 * Deliberately **does not** probe `GET /families/me` the way `SettingsStateHolder` used to: `GET
 * /devices` works without a family (001 §1.5.4/§4), and [isParent] is instead constructor-injected
 * from the caller's own cached launch-probe header (specs/010 §1.2's drawer header, already
 * threaded through `FindlyNavHost`) — the exact mirror of iOS's
 * `DeviceSettingsViewModel(apiClient:isParent:)`. In practice the Devices drawer item is only ever
 * reachable from the Family Map root, which itself requires a family (010 §1.1's launch table), so
 * `isParent` is well-defined by the time this screen is reachable at all; [load]'s defensive
 * `FAMILY_NOT_FOUND` handling below exists only because the shared [ProfileDeadEndRouting]
 * classifier is applied uniformly, not because that path is actually exercised today.
 *
 * Every mutation is per-card: [setTracking]/[setSyncInterval]/[rename] only ever update the one
 * [DeviceCardUi] they target — a failure sets `error` **on that card**, never a shared top-of-list
 * banner (specs/010 §4.2's "errors render on this card" rule, replacing iOS's retired
 * `lastActionError`), and one card's in-progress [DeviceCardUi.renameDraft] is never touched by a
 * sibling card's mutation, or by *this* card's own tracking/interval mutation (only a successful
 * [rename] ever overwrites the draft, with the server's own echoed value).
 */
class DevicesStateHolder(
    private val devicesApi: DevicesApi,
    val isParent: Boolean,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<DevicesUiState>(DevicesUiState.Loading)
    val state: StateFlow<DevicesUiState> = _state.asStateFlow()

    init {
        scope.launch { load() }
    }

    suspend fun load() {
        _state.value = DevicesUiState.Loading
        when (val result = devicesApi.listDevices()) {
            is ApiResult.Failure -> {
                // familyScoped = false: GET /devices needs only a profile (001 §1.5.4) — see this
                // class's doc for why FAMILY_NOT_FOUND is handled defensively, not because it's
                // reachable in practice.
                val variant = ProfileDeadEndRouting.classify(result.error, familyScoped = false)
                _state.value = if (variant != null) {
                    DevicesUiState.RouteToOnboarding(variant)
                } else {
                    DevicesUiState.Error(result.error.userMessage())
                }
            }
            is ApiResult.Success -> {
                _state.value = DevicesUiState.Content(
                    devices = result.data.devices.map { it.toCardUi() },
                    limits = result.features?.limits,
                )
            }
        }
    }

    /** Local-only edit of one card's in-progress rename text — no network call, no commit
     * (specs/010 §4.2: rename has its own explicit Save, unlike the toggle/dropdown below). */
    fun updateRenameDraft(deviceId: String, draft: String) {
        withCard(deviceId) { it.copy(renameDraft = draft) }
    }

    /** §4.2 tracking toggle — commits immediately, unchanged from the retired
     * `SettingsStateHolder.updateDeviceSettings`'s behavior for this field. */
    suspend fun setTracking(deviceId: String, enabled: Boolean) =
        mutate(deviceId, UpdateDeviceRequestDto(trackingEnabled = enabled), syncsRenameDraft = false)

    /** §4.2 sync-interval `FindlyDropdownField` — selecting a value commits immediately, no
     * separate Save (010 §4.2: "no Save button"). */
    suspend fun setSyncInterval(deviceId: String, minutes: Int) =
        mutate(deviceId, UpdateDeviceRequestDto(syncIntervalMinutes = minutes), syncsRenameDraft = false)

    /** §4.2 rename row's Save action — the state-holder support [com.findly.android.network.dto
     * .UpdateDeviceRequestDto.deviceName] parameter has existed, unused, since A2; this is its
     * first real caller. */
    suspend fun rename(deviceId: String, name: String) =
        mutate(deviceId, UpdateDeviceRequestDto(deviceName = name), syncsRenameDraft = true)

    private fun withCard(deviceId: String, transform: (DeviceCardUi) -> DeviceCardUi) {
        val current = _state.value as? DevicesUiState.Content ?: return
        _state.value = current.copy(
            devices = current.devices.map { card -> if (card.deviceId == deviceId) transform(card) else card },
        )
    }

    private suspend fun mutate(deviceId: String, request: UpdateDeviceRequestDto, syncsRenameDraft: Boolean) {
        val current = _state.value as? DevicesUiState.Content ?: return
        if (current.devices.none { it.deviceId == deviceId }) return

        if (!isParent) {
            withCard(deviceId) { it.copy(error = NOT_PARENT_MESSAGE) }
            return
        }

        withCard(deviceId) { it.copy(isMutating = true, error = null) }
        when (val result = devicesApi.updateDevice(deviceId, request)) {
            is ApiResult.Success -> withCard(deviceId) { card ->
                card.copy(
                    deviceName = result.data.deviceName,
                    syncIntervalMinutes = result.data.syncIntervalMinutes,
                    trackingEnabled = result.data.trackingEnabled,
                    // Only a genuine rename commit re-syncs the draft to the server's echoed
                    // value — a tracking/interval mutation's response also carries the
                    // (unchanged) deviceName, but overwriting the draft with it here would
                    // clobber an unrelated in-progress rename edit on this same card.
                    renameDraft = if (syncsRenameDraft) result.data.deviceName else card.renameDraft,
                    isMutating = false,
                    error = null,
                )
            }
            is ApiResult.Failure -> withCard(deviceId) { it.copy(isMutating = false, error = result.error.userMessage()) }
        }
    }
}

private fun FamilyDeviceDto.toCardUi(): DeviceCardUi = DeviceCardUi(
    deviceId = deviceId,
    deviceName = deviceName,
    model = model,
    platform = platform,
    syncIntervalMinutes = syncIntervalMinutes,
    trackingEnabled = trackingEnabled,
    pushInvalid = pushInvalid,
    ownerDisplayName = ownerDisplayName,
    lastSeenAt = lastSeenAt,
    renameDraft = deviceName,
)
