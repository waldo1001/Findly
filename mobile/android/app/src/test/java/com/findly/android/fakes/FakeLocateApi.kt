package com.findly.android.fakes

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.FulfillFixDto
import com.findly.android.network.dto.FulfillResponseDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.dto.LocateRequestStatusResponseDto
import com.findly.android.network.ports.LocateApi
import java.util.ArrayDeque

/** Test fake — mirrors the backend's `test/fakes/` convention (backend/README.md). Used by
 * `LocateStateHolderTest` to script the poll-until-terminal sequence (001-api-contract.md §6.2):
 * [pollResults] is drained in order, one entry per [getLocateRequest] call; once exhausted, the
 * last dequeued result is repeated so a test doesn't have to over-provision the queue. */
class FakeLocateApi : LocateApi {
    val createLocateRequestCalls = mutableListOf<Pair<String?, String?>>()
    val getLocateRequestCalls = mutableListOf<String>()

    var createLocateRequestResult: ApiResult<LocateRequestDto> = ApiResult.Success(
        LocateRequestDto(
            requestId = "lr_test",
            status = "pending",
            targetUserId = "u2",
            targetDeviceId = "device-2",
            expiresAt = "2026-07-19T09:06:12Z",
            lastKnown = null,
        ),
        features = defaultFeatures(),
    )

    val pollResults: ArrayDeque<ApiResult<LocateRequestStatusResponseDto>> = ArrayDeque()
    private var lastPollResult: ApiResult<LocateRequestStatusResponseDto>? = null

    var fulfillLocateRequestResult: ApiResult<FulfillResponseDto> = ApiResult.Success(
        FulfillResponseDto(status = "fulfilled"),
        features = defaultFeatures(),
    )

    override suspend fun createLocateRequest(
        targetUserId: String?,
        targetDeviceId: String?,
    ): ApiResult<LocateRequestDto> {
        createLocateRequestCalls.add(targetUserId to targetDeviceId)
        return createLocateRequestResult
    }

    override suspend fun getLocateRequest(requestId: String): ApiResult<LocateRequestStatusResponseDto> {
        getLocateRequestCalls.add(requestId)
        val next = if (pollResults.isEmpty()) lastPollResult else pollResults.poll()
        requireNotNull(next) { "FakeLocateApi.pollResults was never seeded" }
        lastPollResult = next
        return next
    }

    override suspend fun fulfillLocateRequest(
        requestId: String,
        deviceId: String,
        fix: FulfillFixDto,
    ): ApiResult<FulfillResponseDto> = fulfillLocateRequestResult
}
