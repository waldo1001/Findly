package com.findly.android.network.dto

import kotlinx.serialization.Serializable

// 001-api-contract.md §4 — Devices.

/** §4.1 request. `deviceId`/`platform`/`model`/`appVersion` required; the rest optional.
 * `pushToken`/`locationPushToken` are write-only and MUST be omitted (not sent as explicit
 * `null`) when there is nothing new to send — 001 §4.1's "omitted token fields are left
 * unchanged" pin — kotlinx.serialization omits a property entirely when its value is the
 * declared default (`null`) unless `encodeDefaults` is turned on, which network/FindlyJson.kt
 * deliberately does not do. */
@Serializable
data class RegisterDeviceRequestDto(
    val deviceId: String,
    val platform: String,
    val model: String,
    val appVersion: String,
    val pushToken: String? = null,
    val locationPushToken: String? = null,
    val deviceName: String? = null,
)

/** §4.1/§4.2/§4.3 response shape. Push tokens never appear here (write-only, §4.1). */
@Serializable
data class DeviceDto(
    val deviceId: String,
    val ownerUserId: String,
    val platform: String,
    val deviceName: String,
    val model: String,
    val appVersion: String,
    val syncIntervalMinutes: Int,
    val trackingEnabled: Boolean,
    val pushInvalid: Boolean,
)

/** §4.2 — same as [DeviceDto] plus roster context. */
@Serializable
data class FamilyDeviceDto(
    val deviceId: String,
    val ownerUserId: String,
    val platform: String,
    val deviceName: String,
    val model: String,
    val appVersion: String,
    val syncIntervalMinutes: Int,
    val trackingEnabled: Boolean,
    val pushInvalid: Boolean,
    val ownerDisplayName: String,
    val lastSeenAt: String? = null,
)

@Serializable
data class ListDevicesResponseDto(
    val devices: List<FamilyDeviceDto>,
)

/** §4.3 request — at least one field. Parent may set any; non-parent owner may set only
 * `pushToken` (server-enforced, §4.3 — 403 otherwise). */
@Serializable
data class UpdateDeviceRequestDto(
    val syncIntervalMinutes: Int? = null,
    val trackingEnabled: Boolean? = null,
    val deviceName: String? = null,
    val pushToken: String? = null,
) {
    fun requireAtLeastOneField(): UpdateDeviceRequestDto = apply {
        require(syncIntervalMinutes != null || trackingEnabled != null || deviceName != null || pushToken != null) {
            "UpdateDeviceRequestDto requires at least one field (001 §4.3)"
        }
    }
}
