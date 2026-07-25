package com.findly.android.network.ports

import com.findly.android.network.ApiResult
import com.findly.android.network.dto.FulfillFixDto
import com.findly.android.network.dto.FulfillResponseDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.dto.LocateRequestStatusResponseDto

/** 001-api-contract.md §6 — Push-to-locate. */
interface LocateApi {
    /** Exactly one of [targetUserId]/[targetDeviceId] — enforced before the call is made
     * (§6.1). */
    suspend fun createLocateRequest(
        targetUserId: String? = null,
        targetDeviceId: String? = null,
    ): ApiResult<LocateRequestDto>

    suspend fun getLocateRequest(requestId: String): ApiResult<LocateRequestStatusResponseDto>

    /** [fix].source MUST be `"locate"` (§6.3). */
    suspend fun fulfillLocateRequest(
        requestId: String,
        deviceId: String,
        fix: FulfillFixDto,
    ): ApiResult<FulfillResponseDto>
}
