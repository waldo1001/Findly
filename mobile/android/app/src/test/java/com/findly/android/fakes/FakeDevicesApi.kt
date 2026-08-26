package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.ListDevicesResponseDto
import com.findly.android.network.dto.RegisterDeviceRequestDto
import com.findly.android.network.dto.UpdateDeviceRequestDto
import com.findly.android.network.ports.DevicesApi

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Records every
 * [registerDevice] call for assertion (A1); A2 adds scriptable [listDevicesResult] /
 * [updateDeviceResult] for the retired `SettingsStateHolderTest`, now
 * [com.findly.android.ui.devices.DevicesStateHolderTest]. */
class FakeDevicesApi : DevicesApi {
    val registerDeviceCalls = mutableListOf<RegisterDeviceRequestDto>()
    val updateDeviceCalls = mutableListOf<Pair<String, UpdateDeviceRequestDto>>()
    var listDevicesCallCount = 0
        private set

    var resultToReturn: ApiResult<DeviceDto> = ApiResult.Success(
        DeviceDto(
            deviceId = "device-1",
            ownerUserId = "uid-test",
            platform = "android",
            deviceName = "Pixel 8",
            model = "Pixel 8",
            appVersion = "1.0.0",
            syncIntervalMinutes = 15,
            trackingEnabled = true,
            pushInvalid = false,
        ),
        features = null,
    )

    var listDevicesResult: ApiResult<ListDevicesResponseDto> = ApiResult.Success(
        ListDevicesResponseDto(devices = emptyList()),
        features = defaultFeatures(),
    )

    var updateDeviceResult: ApiResult<DeviceDto> = ApiResult.Success(
        DeviceDto(
            deviceId = "device-1",
            ownerUserId = "uid-test",
            platform = "android",
            deviceName = "Pixel 8",
            model = "Pixel 8",
            appVersion = "1.0.0",
            syncIntervalMinutes = 30,
            trackingEnabled = false,
            pushInvalid = false,
        ),
        features = defaultFeatures(),
    )

    override suspend fun registerDevice(request: RegisterDeviceRequestDto): ApiResult<DeviceDto> {
        registerDeviceCalls.add(request)
        return resultToReturn
    }

    override suspend fun listDevices(): ApiResult<ListDevicesResponseDto> {
        listDevicesCallCount++
        return listDevicesResult
    }

    override suspend fun updateDevice(deviceId: String, request: UpdateDeviceRequestDto): ApiResult<DeviceDto> {
        updateDeviceCalls.add(deviceId to request)
        return updateDeviceResult
    }
}
