package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.DeviceSettingsDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import com.findly.android.network.dto.LocationFixDto
import com.findly.android.network.dto.LocationHistoryResponseDto
import com.findly.android.network.dto.ReportLocationsResponseDto
import com.findly.android.network.ports.LocationsApi
import java.util.ArrayDeque

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Scripts a
 * single canned [nextResult] per call for `LocationSyncCoordinatorTest` (A1); A2 adds
 * [getLatestLocationsResult] (`MapStateHolderTest`) and the [historyResults] queue —one entry per
 * `getLocationHistory` call, so cursor pagination (`HistoryStateHolderTest`) can script a
 * different page per call, the same convention as `FakeLocateApi.pollResults`. */
class FakeLocationsApi : LocationsApi {
    val reportLocationsCalls = mutableListOf<Triple<String, String, List<LocationFixDto>>>()
    val getLocationHistoryCalls = mutableListOf<GetLocationHistoryCall>()
    var getLatestLocationsCallCount = 0
        private set

    data class GetLocationHistoryCall(
        val userId: String,
        val from: String,
        val to: String,
        val deviceId: String?,
        val limit: Int?,
        val cursor: String?,
    )

    var nextResult: ApiResult<ReportLocationsResponseDto> = ApiResult.Success(
        ReportLocationsResponseDto(
            accepted = 0,
            duplicates = 0,
            lastKnownUpdated = false,
            deviceSettings = DeviceSettingsDto(15, true),
            geofenceEtag = "\"0\"",
        ),
        features = null,
    )

    var getLatestLocationsResult: ApiResult<LatestLocationsResponseDto> = ApiResult.Success(
        LatestLocationsResponseDto(members = emptyList()),
        features = defaultFeatures(),
    )

    /** One entry per expected `getLocationHistory` call; drained in order. Once exhausted, the
     * last dequeued result repeats. */
    val historyResults: ArrayDeque<ApiResult<LocationHistoryResponseDto>> = ArrayDeque()
    private var lastHistoryResult: ApiResult<LocationHistoryResponseDto>? = null

    override suspend fun reportLocations(
        deviceId: String,
        batchId: String,
        fixes: List<LocationFixDto>,
    ): ApiResult<ReportLocationsResponseDto> {
        reportLocationsCalls.add(Triple(deviceId, batchId, fixes))
        return nextResult
    }

    override suspend fun getLatestLocations(): ApiResult<LatestLocationsResponseDto> {
        getLatestLocationsCallCount++
        return getLatestLocationsResult
    }

    override suspend fun getLocationHistory(
        userId: String,
        from: String,
        to: String,
        deviceId: String?,
        limit: Int?,
        cursor: String?,
    ): ApiResult<LocationHistoryResponseDto> {
        getLocationHistoryCalls.add(GetLocationHistoryCall(userId, from, to, deviceId, limit, cursor))
        val next = if (historyResults.isEmpty()) lastHistoryResult else historyResults.poll()
        requireNotNull(next) { "FakeLocationsApi.historyResults was never seeded" }
        lastHistoryResult = next
        return next
    }
}
