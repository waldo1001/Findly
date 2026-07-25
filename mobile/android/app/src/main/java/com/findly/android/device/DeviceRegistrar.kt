package com.findly.android.device

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.RegisterDeviceRequestDto
import com.findly.android.network.ports.DevicesApi

/**
 * Builds and sends the 001-api-contract.md §4.1 register/update-device request
 * (specs/003-android-client.md §8). Called on: first sign-in, every push-token refresh (§9,
 * via [onPushTokenRefreshed]), and (A2) every app update. Takes `uid` explicitly rather than
 * depending on `AuthProvider` directly, keeping this class decoupled from auth-state plumbing.
 */
class DeviceRegistrar(
    private val devicesApi: DevicesApi,
    private val deviceIdProvider: DeviceIdProvider,
    private val deviceInfoProvider: DeviceInfoProvider,
) {
    suspend fun registerOrUpdate(
        uid: String,
        pushToken: String? = null,
        locationPushToken: String? = null,
        deviceName: String? = null,
    ): ApiResult<DeviceDto> {
        val request = RegisterDeviceRequestDto(
            deviceId = deviceIdProvider.deviceIdFor(uid),
            platform = deviceInfoProvider.platform,
            model = deviceInfoProvider.model,
            appVersion = deviceInfoProvider.appVersion,
            pushToken = pushToken,
            locationPushToken = locationPushToken,
            deviceName = deviceName,
        )
        return devicesApi.registerDevice(request)
    }

    /** Wired to `PushTokenProvider.addRefreshListener` in `AppContainer` (specs/003 §9,
     * 000-overview.md §O4: "Clients MUST re-POST /devices on token refresh"). */
    suspend fun onPushTokenRefreshed(uid: String, newToken: String): ApiResult<DeviceDto> =
        registerOrUpdate(uid = uid, pushToken = newToken)
}
