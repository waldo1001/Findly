package com.findly.android.ui.settings

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.FamilyDeviceDto
import com.findly.android.network.dto.MemberDto
import com.findly.android.network.dto.UpdateDeviceRequestDto
import com.findly.android.network.dto.UpdateMemberRequestDto
import com.findly.android.network.ports.DevicesApi
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.userMessage
import com.findly.android.ui.onboarding.ProfileDeadEndRouting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val NOT_PARENT_MESSAGE = "Only a parent can do this"

/**
 * The device/family-settings screen's pure state machine (001-api-contract.md §3.5/§3.6/§4.2/
 * §4.3). Constructor-injected [CoroutineScope] — same pattern as
 * [com.findly.android.ui.home.HomeStateHolder]. Every mutation is gated by [isParent] —
 * §3.5/§3.6/§4.3 are parent-only server-side too, but gating client-side first avoids a pointless
 * round trip and lets the screen disable controls outright for a non-parent viewer.
 */
class SettingsStateHolder(
    private val familyApi: FamilyApi,
    private val devicesApi: DevicesApi,
    scope: CoroutineScope,
) {
    private val _state = MutableStateFlow<SettingsUiState>(SettingsUiState.Loading)
    val state: StateFlow<SettingsUiState> = _state.asStateFlow()

    init {
        scope.launch { load() }
    }

    val isParent: Boolean get() = (_state.value as? SettingsUiState.Content)?.myRole == "parent"

    suspend fun load() {
        _state.value = SettingsUiState.Loading
        when (val familyResult = familyApi.getMyFamily()) {
            is ApiResult.Failure -> {
                // specs/010-app-shell-and-screen-ux.md §2.1: both GET /families/me and
                // GET /devices are family-scoped (001 §1.6 — "member") for this screen's purposes
                // (Devices and Family, pending their A35 split out of this monolith).
                val variant = ProfileDeadEndRouting.classify(familyResult.error, familyScoped = true)
                _state.value = if (variant != null) {
                    SettingsUiState.RouteToOnboarding(variant)
                } else {
                    SettingsUiState.Error(familyResult.error.userMessage())
                }
                return
            }
            is ApiResult.Success -> {
                when (val devicesResult = devicesApi.listDevices()) {
                    is ApiResult.Failure -> {
                        val variant = ProfileDeadEndRouting.classify(devicesResult.error, familyScoped = true)
                        _state.value = if (variant != null) {
                            SettingsUiState.RouteToOnboarding(variant)
                        } else {
                            SettingsUiState.Error(devicesResult.error.userMessage())
                        }
                    }
                    is ApiResult.Success -> {
                        _state.value = SettingsUiState.Content(
                            myRole = familyResult.data.me.role,
                            members = familyResult.data.members.map { it.toUi() },
                            devices = devicesResult.data.devices.map { it.toUi() },
                        )
                    }
                }
            }
        }
    }

    /** §4.3 — pause/resume ([trackingEnabled]) and sync-interval changes; parent-only. */
    suspend fun updateDeviceSettings(
        deviceId: String,
        syncIntervalMinutes: Int? = null,
        trackingEnabled: Boolean? = null,
        deviceName: String? = null,
    ) {
        val current = _state.value as? SettingsUiState.Content ?: return
        if (current.myRole != "parent") {
            _state.value = current.copy(mutationError = NOT_PARENT_MESSAGE)
            return
        }

        _state.value = current.copy(isMutating = true, mutationError = null)
        val request = UpdateDeviceRequestDto(syncIntervalMinutes, trackingEnabled, deviceName)
        when (val result = devicesApi.updateDevice(deviceId, request)) {
            is ApiResult.Success -> {
                val updated = current.devices.map { device ->
                    if (device.deviceId == deviceId) {
                        device.copy(
                            syncIntervalMinutes = result.data.syncIntervalMinutes,
                            trackingEnabled = result.data.trackingEnabled,
                            deviceName = result.data.deviceName,
                        )
                    } else {
                        device
                    }
                }
                _state.value = current.copy(devices = updated, isMutating = false)
            }
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §3.5 — role/displayName; parent-only. */
    suspend fun updateMember(userId: String, role: String? = null, displayName: String? = null) {
        val current = _state.value as? SettingsUiState.Content ?: return
        if (current.myRole != "parent") {
            _state.value = current.copy(mutationError = NOT_PARENT_MESSAGE)
            return
        }

        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = familyApi.updateMember(userId, UpdateMemberRequestDto(role, displayName))) {
            is ApiResult.Success -> {
                val updated = current.members.map { member -> if (member.userId == userId) result.data.toUi() else member }
                _state.value = current.copy(members = updated, isMutating = false)
            }
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }

    /** §3.6 — bare 204; parent-only. The server rejects the last-parent removing themselves
     * (`lastParent`) — surfaced here as an ordinary [mutationError], not special-cased. */
    suspend fun removeMember(userId: String) {
        val current = _state.value as? SettingsUiState.Content ?: return
        if (current.myRole != "parent") {
            _state.value = current.copy(mutationError = NOT_PARENT_MESSAGE)
            return
        }

        _state.value = current.copy(isMutating = true, mutationError = null)
        when (val result = familyApi.removeMember(userId)) {
            is ApiResult.Success -> _state.value = current.copy(
                members = current.members.filterNot { it.userId == userId },
                isMutating = false,
            )
            is ApiResult.Failure -> _state.value = current.copy(isMutating = false, mutationError = result.error.userMessage())
        }
    }
}

private fun MemberDto.toUi(): MemberUi = MemberUi(userId, role, displayName, joinedAt)

private fun FamilyDeviceDto.toUi(): DeviceUi = DeviceUi(
    deviceId = deviceId,
    deviceName = deviceName,
    model = model,
    platform = platform,
    syncIntervalMinutes = syncIntervalMinutes,
    trackingEnabled = trackingEnabled,
    pushInvalid = pushInvalid,
    ownerDisplayName = ownerDisplayName,
    lastSeenAt = lastSeenAt,
)
