package com.findly.android.network.ports

import com.findly.android.network.ApiResult
import com.findly.android.network.ETagged
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceDto
import com.findly.android.network.dto.GeofenceEventHistoryResponseDto
import com.findly.android.network.dto.GeofenceEventInputDto
import com.findly.android.network.dto.GeofenceEventsResponseDto

/** 001-api-contract.md §7 — Geofences. */
interface GeofenceApi {
    /** `Success(null, features = null)` means "304 Not Modified" (specs/003 §6.3). */
    suspend fun getGeofences(ifNoneMatch: String? = null): ApiResult<ETagged<GeofenceConfigResponseDto>?>

    suspend fun replaceGeofences(
        ifMatch: String,
        geofences: List<GeofenceDto>,
    ): ApiResult<ETagged<GeofenceConfigResponseDto>>

    suspend fun reportGeofenceEvents(
        deviceId: String,
        events: List<GeofenceEventInputDto>,
    ): ApiResult<GeofenceEventsResponseDto>

    suspend fun getGeofenceEventHistory(
        from: String,
        to: String,
        userId: String? = null,
        limit: Int? = null,
        cursor: String? = null,
    ): ApiResult<GeofenceEventHistoryResponseDto>
}
