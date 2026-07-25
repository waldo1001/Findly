package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.ETagged
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceDto
import com.findly.android.network.dto.GeofenceEventHistoryResponseDto
import com.findly.android.network.dto.GeofenceEventInputDto
import com.findly.android.network.dto.GeofenceEventsResponseDto
import com.findly.android.network.ports.GeofenceApi

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Used by
 * `GeofencesStateHolderTest` to script the ETag get/put/conflict flow (001-api-contract.md
 * §7.1–7.2). */
class FakeGeofenceApi : GeofenceApi {
    val getGeofencesCalls = mutableListOf<String?>()
    val replaceGeofencesCalls = mutableListOf<Pair<String, List<GeofenceDto>>>()

    var getGeofencesResult: ApiResult<ETagged<GeofenceConfigResponseDto>?> = ApiResult.Success(
        ETagged(GeofenceConfigResponseDto(version = 1, geofences = emptyList()), "\"1\""),
        features = defaultFeatures(),
    )

    var replaceGeofencesResult: ApiResult<ETagged<GeofenceConfigResponseDto>> = ApiResult.Success(
        ETagged(GeofenceConfigResponseDto(version = 2, geofences = emptyList()), "\"2\""),
        features = defaultFeatures(),
    )

    override suspend fun getGeofences(ifNoneMatch: String?): ApiResult<ETagged<GeofenceConfigResponseDto>?> {
        getGeofencesCalls.add(ifNoneMatch)
        return getGeofencesResult
    }

    override suspend fun replaceGeofences(
        ifMatch: String,
        geofences: List<GeofenceDto>,
    ): ApiResult<ETagged<GeofenceConfigResponseDto>> {
        replaceGeofencesCalls.add(ifMatch to geofences)
        return replaceGeofencesResult
    }

    override suspend fun reportGeofenceEvents(
        deviceId: String,
        events: List<GeofenceEventInputDto>,
    ): ApiResult<GeofenceEventsResponseDto> =
        throw UnsupportedOperationException("not exercised by A2 tests")

    override suspend fun getGeofenceEventHistory(
        from: String,
        to: String,
        userId: String?,
        limit: Int?,
        cursor: String?,
    ): ApiResult<GeofenceEventHistoryResponseDto> =
        throw UnsupportedOperationException("not exercised by A2 tests")
}
