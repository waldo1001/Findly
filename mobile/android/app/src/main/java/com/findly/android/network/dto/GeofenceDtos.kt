package com.findly.android.network.dto

import kotlinx.serialization.Serializable

// 001-api-contract.md §7 — Geofences.

@Serializable
data class GeofenceDto(
    val geofenceId: String,
    val name: String,
    val lat: Double,
    val lon: Double,
    val radiusM: Double,
    val icon: String,
    val notifyOnEnter: Boolean,
    val notifyOnExit: Boolean,
)

@Serializable
data class GeofenceConfigResponseDto(
    val version: Int,
    val geofences: List<GeofenceDto>,
)

@Serializable
data class ReplaceGeofencesRequestDto(
    val geofences: List<GeofenceDto>,
)

@Serializable
data class GeofenceEventInputDto(
    val eventId: String,
    val geofenceId: String,
    val transition: String,
    val recordedAt: String,
)

@Serializable
data class ReportGeofenceEventsRequestDto(
    val events: List<GeofenceEventInputDto>,
)

/** §7.3 response — same piggyback shape as §5.1 minus `lastKnownUpdated`. */
@Serializable
data class GeofenceEventsResponseDto(
    val accepted: Int,
    val duplicates: Int,
    val deviceSettings: DeviceSettingsDto,
    val geofenceEtag: String,
)

/** §7.4 — `geofenceName`/`lat`/`lon`/`radiusM` are `null` when the event's `geofenceId` was
 * unknown at write time (stale device config, §7.3). */
@Serializable
data class GeofenceEventRecordDto(
    val userId: String,
    val deviceId: String,
    val geofenceId: String,
    val geofenceName: String? = null,
    val lat: Double? = null,
    val lon: Double? = null,
    val radiusM: Double? = null,
    val transition: String,
    val recordedAt: String,
    val receivedAt: String,
)

@Serializable
data class GeofenceEventHistoryResponseDto(
    val events: List<GeofenceEventRecordDto>,
    val nextCursor: String? = null,
)
