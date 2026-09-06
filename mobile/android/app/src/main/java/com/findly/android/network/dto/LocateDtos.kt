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

/** B26 (2026-09-06) added `createdAt` to this response — A39's requester side needs it to compare
 * against `GET /locations/latest`'s `recordedAt` once polling stops (specs/009 §5.1 "Requester
 * side"). */
@Serializable
data class LocateRequestDto(
    val requestId: String,
    val status: String,
    val targetUserId: String? = null,
    val targetDeviceId: String,
    val createdAt: String,
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

/** B26 (2026-09-06) added `createdAt`, `fulfilledAt`, and `late` to this response — `late` is
 * `true` when the fulfil landed inside the 10-minute grace after `expiresAt` (001 §6.2/§6.3);
 * `expired` itself is not final in that case (a §6.3 fulfil can still flip it to `fulfilled`), so
 * A39's requester-side polling watches `late` rather than treating `expired` as automatically
 * meaning "no answer". */
@Serializable
data class LocateRequestStatusResponseDto(
    val requestId: String,
    val status: String,
    val createdAt: String,
    val expiresAt: String,
    val fulfilledAt: String? = null,
    val late: Boolean = false,
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
