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
 * §7.1–7.2), and (A11) `GeofenceEventSyncCoordinatorTest`/`LocationSyncRunnerTest` to script the
 * §7.3 event-report piggyback flow. */
class FakeGeofenceApi : GeofenceApi {
    val getGeofencesCalls = mutableListOf<String?>()
    val replaceGeofencesCalls = mutableListOf<Pair<String, List<GeofenceDto>>>()
    val reportGeofenceEventsCalls = mutableListOf<Pair<String, List<GeofenceEventInputDto>>>()

    var getGeofencesResult: ApiResult<ETagged<GeofenceConfigResponseDto>?> = ApiResult.Success(
        ETagged(GeofenceConfigResponseDto(version = 1, geofences = emptyList()), "\"1\""),
        features = defaultFeatures(),
    )

    var replaceGeofencesResult: ApiResult<ETagged<GeofenceConfigResponseDto>> = ApiResult.Success(
        ETagged(GeofenceConfigResponseDto(version = 2, geofences = emptyList()), "\"2\""),
        features = defaultFeatures(),
    )

    var reportGeofenceEventsResult: ApiResult<GeofenceEventsResponseDto> = ApiResult.Success(
        GeofenceEventsResponseDto(
            accepted = 0,
            duplicates = 0,
            deviceSettings = com.findly.android.network.dto.DeviceSettingsDto(15, true),
            geofenceEtag = "\"0\"",
        ),
        features = null,
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
    ): ApiResult<GeofenceEventsResponseDto> {
        reportGeofenceEventsCalls.add(deviceId to events)
        return reportGeofenceEventsResult
    }

    override suspend fun getGeofenceEventHistory(
        from: String,
        to: String,
        userId: String?,
        limit: Int?,
        cursor: String?,
    ): ApiResult<GeofenceEventHistoryResponseDto> =
        throw UnsupportedOperationException("not exercised by A2 tests")
}
