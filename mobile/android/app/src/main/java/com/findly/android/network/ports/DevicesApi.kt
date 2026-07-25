package com.findly.android.network.ports

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.ListDevicesResponseDto
import com.findly.android.network.dto.RegisterDeviceRequestDto
import com.findly.android.network.dto.UpdateDeviceRequestDto

/** 001-api-contract.md §4 — Devices. */
interface DevicesApi {
    suspend fun registerDevice(request: RegisterDeviceRequestDto): ApiResult<DeviceDto>
    suspend fun listDevices(): ApiResult<ListDevicesResponseDto>
    suspend fun updateDevice(deviceId: String, request: UpdateDeviceRequestDto): ApiResult<DeviceDto>
}
