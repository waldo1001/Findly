package com.findly.android.location.settings

import com.findly.android.network.ApiError
import com.findly.android.network.ApiResult
import com.findly.android.network.DeviceSettingsSnapshot
import com.findly.android.network.ports.DevicesApi

sealed class PollOutcome {
    data object Applied : PollOutcome()

    /** This device's own row wasn't in the family roster response — e.g. it was deleted. Mirrors
     * specs/009-device-runtime.md §9's `DEVICE_NOT_FOUND` handling one level up (the endpoint
     * itself returned 200, just without this device in it); the caller reacts the same way. */
    data object DeviceNotFound : PollOutcome()
    data class Failed(val error: ApiError) : PollOutcome()
}

/**
 * The pull-based settings poll (specs/009-device-runtime.md §4 / §3.5's third path): fetches
 * this device's row from `GET /devices` (001-api-contract.md §4.2 — the only settings-read
 * endpoint; there is no "get my own device" call, so the family-wide list is filtered by
 * [deviceId]) and applies it through [DeviceSettingsCoordinator]. Callable from **both** §4's
 * required triggers — app foreground and the low-frequency ≥6-hourly background check
 * (`SettingsPollWorker`) — this one method is the single implementation both call. Harmless to
 * call when not paused: [DeviceSettingsCoordinator.applySettings] is a no-op unless something
 * actually changed.
 */
class SettingsPoller(
    private val devicesApi: DevicesApi,
    private val deviceId: String,
    private val settingsCoordinator: DeviceSettingsCoordinator,
) {
    suspend fun poll(): PollOutcome {
        return when (val result = devicesApi.listDevices()) {
            is ApiResult.Success -> {
                val own = result.data.devices.firstOrNull { it.deviceId == deviceId }
                    ?: return PollOutcome.DeviceNotFound
                settingsCoordinator.applySettings(
                    DeviceSettingsSnapshot(own.syncIntervalMinutes, own.trackingEnabled),
                )
                PollOutcome.Applied
            }
            is ApiResult.Failure -> PollOutcome.Failed(result.error)
        }
    }
}
