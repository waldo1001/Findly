package com.findly.android.network.dto

import kotlinx.serialization.Serializable

// 001-api-contract.md §5 — Location reporting & reading.

/** A single fix as sent on the wire (§5.1). `source` is one of "periodic"|"locate"|"geofence"|
 * "manual" — see queue/QueuedFix.kt for the typed Kotlin enum + mapping. */
@Serializable
data class LocationFixDto(
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
data class ReportLocationsRequestDto(
    val batchId: String,
    val fixes: List<LocationFixDto>,
)

/** The piggybacked settings/config-etag block (§5.1, §7.3). */
@Serializable
data class DeviceSettingsDto(
    val syncIntervalMinutes: Int,
    val trackingEnabled: Boolean,
)

@Serializable
data class ReportLocationsResponseDto(
    val accepted: Int,
    val duplicates: Int,
    val lastKnownUpdated: Boolean,
    val deviceSettings: DeviceSettingsDto,
    val geofenceEtag: String,
)

/** §5.2 — one entry per device. Every field beyond `deviceId`/`deviceName`/`trackingEnabled`/
 * `syncIntervalMinutes` is nullable: 001 explicitly documents `lat`/`lon`/`recordedAt`/`isStale`
 * as `null` for a never-reported device, and the neighboring fields (`accuracyM`, `batteryPct`,
 * `source`, `receivedAt`) are made nullable too, defensively, for the same state (specs/003
 * §5's DTO-nullability note). */
@Serializable
data class LatestDeviceDto(
    val deviceId: String,
    val deviceName: String,
    val lat: Double? = null,
    val lon: Double? = null,
    val accuracyM: Double? = null,
    val recordedAt: String? = null,
    val receivedAt: String? = null,
    val batteryPct: Int? = null,
    val source: String? = null,
    val trackingEnabled: Boolean,
    val syncIntervalMinutes: Int,
    val isStale: Boolean? = null,
)

@Serializable
data class LatestMemberDto(
    val userId: String,
    val displayName: String,
    val devices: List<LatestDeviceDto>,
)

@Serializable
data class LatestLocationsResponseDto(
    val members: List<LatestMemberDto>,
)

/** §5.3 — a stored history point. All fields are guaranteed non-null at write time (§5.1's
 * required fields), unlike [LatestDeviceDto]'s "no report yet" state. */
@Serializable
data class HistoryPointDto(
    val deviceId: String,
    val recordedAt: String,
    val lat: Double,
    val lon: Double,
    val accuracyM: Double,
    val batteryPct: Int,
    val source: String,
)

@Serializable
data class LocationHistoryResponseDto(
    val points: List<HistoryPointDto>,
    val nextCursor: String? = null,
)
