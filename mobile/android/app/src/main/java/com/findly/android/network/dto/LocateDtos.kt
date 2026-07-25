package com.findly.android.network.dto

import kotlinx.serialization.Serializable

// 001-api-contract.md §6 — Push-to-locate.

/** §6.1 — exactly one of `targetUserId`/`targetDeviceId`. [requireExactlyOneTarget] enforces the
 * rule client-side before the call is made. */
@Serializable
data class CreateLocateRequestRequestDto(
    val targetUserId: String? = null,
    val targetDeviceId: String? = null,
) {
    fun requireExactlyOneTarget(): CreateLocateRequestRequestDto = apply {
        require((targetUserId != null) xor (targetDeviceId != null)) {
            "CreateLocateRequestRequestDto requires exactly one of targetUserId/targetDeviceId (001 §6.1)"
        }
    }
}

@Serializable
data class LastKnownDto(
    val deviceId: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val recordedAt: String,
)

@Serializable
data class LocateRequestDto(
    val requestId: String,
    val status: String,
    val targetUserId: String? = null,
    val targetDeviceId: String,
    val expiresAt: String,
    val lastKnown: LastKnownDto? = null,
)

/** §6.2's `fix` shape: §5.1's fix fields plus `deviceId` (the fix's own shape doesn't otherwise
 * carry which device it came from). */
@Serializable
data class LocateFixDto(
    val deviceId: String,
    val fixId: String,
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val altitudeM: Double? = null,
    val speedMps: Double? = null,
    val bearingDeg: Double? = null,
    val batteryPct: Int,
    val source: String,
)

@Serializable
data class LocateRequestStatusResponseDto(
    val requestId: String,
    val status: String,
    val expiresAt: String,
    val fix: LocateFixDto? = null,
)

/** §6.3 — `source` MUST be `"locate"` (enforced by [FulfillLocateRequestRequestDto]'s factory in
 * network/FindlyApiClient.kt, not here, to keep this a plain data holder). */
@Serializable
data class FulfillFixDto(
    val fixId: String,
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val altitudeM: Double? = null,
    val speedMps: Double? = null,
    val bearingDeg: Double? = null,
    val batteryPct: Int,
    val source: String,
)

@Serializable
data class FulfillLocateRequestRequestDto(
    val fix: FulfillFixDto,
)

@Serializable
data class FulfillResponseDto(
    val status: String,
)
