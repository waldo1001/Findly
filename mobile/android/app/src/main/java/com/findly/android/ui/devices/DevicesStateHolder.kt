package com.findly.android.ui.devices

import com.findly.android.network.ApiError
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
    /** A41 (specs/010 §4.2): this app instance's own registered `deviceId` — `null` only for a
     * caller that genuinely cannot resolve it yet (mirrors `AppContainer`'s own nullable
     * `deviceIdFor` seam). Marks exactly one card [DeviceCardUi.isThisDevice] when it matches.
     * Code-review fix (A41 round 2, finding 9): a supplier, called fresh from every [load] rather
     * than a value captured once at construction — `container.localDeviceIdOrNull()` can resolve
     * `null` mid sign-out/sign-in (auth state not yet `SignedIn`), and a plain snapshot would then
     * cache `null` for this whole `ViewModel`'s lifetime, never marking a card even after sign-in
     * completes and a later [load] re-runs. */
    private val localDeviceId: () -> String? = { null },
    /** The signed-in caller's uid (matches `ownerUserId`), resolved fresh per [load] like
     * [localDeviceId] — decides ownership for the nudge toggle and the Remove action
     * (specs/011 §1.1, §4.4). */
    private val localUserId: () -> String? = { null },
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
                // Resolved fresh on every load() (finding 9) - see localDeviceId's own doc.
                val currentLocalDeviceId = localDeviceId()
                val currentLocalUserId = localUserId()
                _state.value = DevicesUiState.Content(
                    devices = result.data.devices.map {
                        it.toCardUi(
                            isThisDevice = it.deviceId == currentLocalDeviceId,
                            isOwner = currentLocalUserId != null && it.ownerUserId == currentLocalUserId,
                            isParent = isParent,
                        )
                    },
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

    /** 011 §1.1: opens the Remove confirmation — ignored unless the action is available. */
    fun requestRemove(deviceId: String) {
        val card = cardOrNull(deviceId) ?: return
        if (!card.canRemove) return
        withCard(deviceId) { it.copy(isConfirmingRemoval = true, error = null) }
    }

    fun cancelRemove(deviceId: String) {
        withCard(deviceId) { it.copy(isConfirmingRemoval = false) }
    }

    /** 011 §1.1: `204` and `DEVICE_NOT_FOUND` both mean the device is gone (the latter also
     * refreshes the list); `AUTH_FORBIDDEN` renders on the card. */
    suspend fun confirmRemove(deviceId: String) {
        val card = cardOrNull(deviceId) ?: return
        if (!card.canRemove || !card.isConfirmingRemoval) return

        withCard(deviceId) { it.copy(isConfirmingRemoval = false, isMutating = true, error = null) }
        when (val result = devicesApi.deleteDevice(deviceId)) {
            is ApiResult.Success -> dropCard(deviceId)
            is ApiResult.Failure -> when (result.error) {
                is ApiError.DeviceNotFound -> {
                    dropCard(deviceId)
                    load()
                }
                is ApiError.AuthForbidden ->
                    withCard(deviceId) { it.copy(isMutating = false, error = DeviceLifecyclePolicy.REMOVE_FORBIDDEN_MESSAGE) }
                else -> withCard(deviceId) { it.copy(isMutating = false, error = result.error.userMessage()) }
            }
        }
    }

    /** 011 §4.4: owner-only (any role) `Remind me when sharing stops` — commits immediately. */
    suspend fun setStaleNudge(deviceId: String, enabled: Boolean) {
        val card = cardOrNull(deviceId) ?: return
        if (!DeviceLifecyclePolicy.showsNudgeToggle(card.isOwnedByCaller)) return

        withCard(deviceId) { it.copy(isMutating = true, error = null) }
        when (val result = devicesApi.updateDevice(deviceId, UpdateDeviceRequestDto(staleNudgeEnabled = enabled))) {
            is ApiResult.Success -> withCard(deviceId) {
                it.copy(staleNudgeEnabled = result.data.staleNudgeEnabled, isMutating = false, error = null)
            }
            is ApiResult.Failure -> withCard(deviceId) { it.copy(isMutating = false, error = result.error.userMessage()) }
        }
    }

    private fun cardOrNull(deviceId: String): DeviceCardUi? =
        (_state.value as? DevicesUiState.Content)?.devices?.firstOrNull { it.deviceId == deviceId }

    private fun dropCard(deviceId: String) {
        val current = _state.value as? DevicesUiState.Content ?: return
        _state.value = current.copy(devices = current.devices.filterNot { it.deviceId == deviceId })
    }

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

private fun FamilyDeviceDto.toCardUi(isThisDevice: Boolean, isOwner: Boolean, isParent: Boolean): DeviceCardUi = DeviceCardUi(
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
    isThisDevice = isThisDevice,
    isDormant = isDormant,
    staleNudgeEnabled = staleNudgeEnabled,
    isOwnedByCaller = isOwner,
    canRemove = DeviceLifecyclePolicy.canRemove(isParent = isParent, isOwner = isOwner, isThisDevice = isThisDevice),
)
