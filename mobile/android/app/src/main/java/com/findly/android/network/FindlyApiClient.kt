package com.findly.android.network

import com.findly.android.auth.AuthProvider
import com.findly.android.network.dto.*
import com.findly.android.network.ports.DevicesApi
import com.findly.android.network.ports.FamilyApi
import com.findly.android.network.ports.GeofenceApi
import com.findly.android.network.ports.GroupsApi
import com.findly.android.network.ports.LocateApi
import com.findly.android.network.ports.LocationsApi
import java.io.IOException
import okhttp3.ResponseBody
import retrofit2.Response

/**
 * Implements all six API port interfaces on top of [FindlyApiService]
 * (specs/003-android-client.md §5's endpoint table). The only thing the rest of the app depends
 * on for networking — mirrors the backend's ports/adapters split (`backend/README.md`).
 */
class FindlyApiClient(
    private val service: FindlyApiService,
    private val authProvider: AuthProvider,
) : FamilyApi, DevicesApi, LocationsApi, LocateApi, GeofenceApi, GroupsApi {

    // ------------------------------------------------------------------
    // Shared envelope/error handling (specs/003 §6)
    // ------------------------------------------------------------------

    /**
     * The single shared retry-once-on-`AUTH_TOKEN_EXPIRED` helper (001-api-contract.md §2.1/§6.4;
     * carried-over A1 review finding: this logic used to be hand-duplicated in four places —
     * [unwrap], `removeMember`, `getGeofences`, `replaceGeofences` — with only the generic path
     * under test). [attempt] is called once; if its result is a [ApiError.AuthTokenExpired]
     * failure, the ID token is force-refreshed and [attempt] is invoked exactly one more time,
     * regardless of the response's body shape (a normal envelope, a bare 204/`Unit`, or a
     * 304/ETag-wrapped nullable) — every `FindlyApiClient` method funnels its network attempt
     * through this one function.
     */
    private suspend fun <T> withAuthRetry(attempt: suspend () -> ApiResult<T>): ApiResult<T> {
        val result = attempt()
        val error = (result as? ApiResult.Failure)?.error
        return if (error is ApiError.AuthTokenExpired) {
            authProvider.currentIdToken(forceRefresh = true)
            attempt()
        } else {
            result
        }
    }

    private suspend fun <T> unwrapOnce(call: suspend () -> Response<Envelope<T>>): ApiResult<T> = try {
        val response = call()
        if (response.isSuccessful) {
            val body = response.body()
            if (body == null) {
                ApiResult.Failure(ApiError.InternalError("empty success body", null))
            } else {
                ApiResult.Success(body.data, body.features.toDomain())
            }
        } else {
            ApiResult.Failure(parseError(response.errorBody()?.string()))
        }
    } catch (e: IOException) {
        ApiResult.Failure(ApiError.NetworkFailure(e))
    }

    private suspend fun <T> unwrap(call: suspend () -> Response<Envelope<T>>): ApiResult<T> =
        withAuthRetry { unwrapOnce(call) }

    /**
     * Shared bare-204 handling (specs/003 §6.3) — every endpoint whose success body is
     * intentionally empty funnels through here: `removeMember` (§3.6), and (as of specs/005)
     * `deleteGroup`/`leaveGroup`/`removeGroupMember` (§12.5/§12.8/§12.9). Extracted once three
     * more of these appeared alongside `removeMember`, following the same anti-duplication
     * lesson as [withAuthRetry]'s own extraction (A1 review finding).
     */
    private suspend fun unwrapBare204(call: suspend () -> Response<ResponseBody>): ApiResult<Unit> =
        withAuthRetry {
            try {
                val response = call()
                if (response.isSuccessful) {
                    ApiResult.Success(Unit, features = null)
                } else {
                    ApiResult.Failure(parseError(response.errorBody()?.string()))
                }
            } catch (e: IOException) {
                ApiResult.Failure(ApiError.NetworkFailure(e))
            }
        }

    private fun parseError(errorBodyText: String?): ApiError {
        if (errorBodyText.isNullOrEmpty()) {
            return ApiError.InternalError("empty error body", null)
        }
        return try {
            val envelope = FindlyJson.decodeFromString(ErrorEnvelope.serializer(), errorBodyText)
            ApiErrorMapper.fromCode(
                code = envelope.error.code,
                message = envelope.error.message,
                details = envelope.error.details,
                requestId = envelope.error.requestId,
            )
        } catch (e: Exception) {
            ApiError.InternalError("unparseable error body: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // FamilyApi (001 §3)
    // ------------------------------------------------------------------

    override suspend fun createFamily(familyName: String, displayName: String): ApiResult<CreateFamilyResponseDto> =
        unwrap { service.createFamily(CreateFamilyRequestDto(familyName, displayName)) }

    override suspend fun getMyFamily(): ApiResult<FamilyMeResponseDto> =
        unwrap { service.getMyFamily() }

    override suspend fun createInvite(role: String, emailHint: String?): ApiResult<CreateInviteResponseDto> =
        unwrap { service.createInvite(CreateInviteRequestDto(role, emailHint)) }

    override suspend fun acceptInvite(inviteCode: String, displayName: String): ApiResult<AcceptInviteResponseDto> =
        unwrap { service.acceptInvite(AcceptInviteRequestDto(inviteCode, displayName)) }

    override suspend fun updateMember(userId: String, request: UpdateMemberRequestDto): ApiResult<MemberDto> =
        unwrap { service.updateMember(userId, request.requireAtLeastOneField()) }

    override suspend fun removeMember(userId: String): ApiResult<Unit> =
        unwrapBare204 { service.removeMember(userId) }

    // ------------------------------------------------------------------
    // DevicesApi (001 §4)
    // ------------------------------------------------------------------

    override suspend fun registerDevice(request: RegisterDeviceRequestDto): ApiResult<DeviceDto> =
        unwrap { service.registerDevice(request) }

    override suspend fun listDevices(): ApiResult<ListDevicesResponseDto> =
        unwrap { service.listDevices() }

    override suspend fun updateDevice(deviceId: String, request: UpdateDeviceRequestDto): ApiResult<DeviceDto> =
        unwrap { service.updateDevice(deviceId, request.requireAtLeastOneField()) }

    // ------------------------------------------------------------------
    // LocationsApi (001 §5)
    // ------------------------------------------------------------------

    override suspend fun reportLocations(
        deviceId: String,
        batchId: String,
        fixes: List<LocationFixDto>,
    ): ApiResult<ReportLocationsResponseDto> =
        unwrap { service.reportLocations(deviceId, ReportLocationsRequestDto(batchId, fixes)) }

    override suspend fun getLatestLocations(): ApiResult<LatestLocationsResponseDto> =
        unwrap { service.getLatestLocations() }

    override suspend fun getLocationHistory(
        userId: String,
        from: String,
        to: String,
        deviceId: String?,
        limit: Int?,
        cursor: String?,
    ): ApiResult<LocationHistoryResponseDto> =
        unwrap { service.getLocationHistory(userId, from, to, deviceId, limit, cursor) }

    // ------------------------------------------------------------------
    // LocateApi (001 §6)
    // ------------------------------------------------------------------

    override suspend fun createLocateRequest(
        targetUserId: String?,
        targetDeviceId: String?,
    ): ApiResult<LocateRequestDto> = unwrap {
        service.createLocateRequest(
            CreateLocateRequestRequestDto(targetUserId, targetDeviceId).requireExactlyOneTarget(),
        )
    }

    override suspend fun getLocateRequest(requestId: String): ApiResult<LocateRequestStatusResponseDto> =
        unwrap { service.getLocateRequest(requestId) }

    override suspend fun fulfillLocateRequest(
        requestId: String,
        deviceId: String,
        fix: FulfillFixDto,
    ): ApiResult<FulfillResponseDto> {
        require(fix.source == "locate") { "FulfillFixDto.source MUST be \"locate\" (001 §6.3)" }
        return unwrap { service.fulfillLocateRequest(requestId, deviceId, FulfillLocateRequestRequestDto(fix)) }
    }

    // ------------------------------------------------------------------
    // GeofenceApi (001 §7)
    // ------------------------------------------------------------------

    override suspend fun getGeofences(ifNoneMatch: String?): ApiResult<ETagged<GeofenceConfigResponseDto>?> =
        withAuthRetry {
            try {
                val response = service.getGeofences(ifNoneMatch)
                when {
                    response.code() == 304 -> ApiResult.Success(null, features = null)
                    response.isSuccessful -> {
                        val body = response.body()
                        if (body == null) {
                            ApiResult.Failure(ApiError.InternalError("empty success body", null))
                        } else {
                            val etag = response.headers()["ETag"].orEmpty()
                            ApiResult.Success(ETagged(body.data, etag), body.features.toDomain())
                        }
                    }
                    else -> ApiResult.Failure(parseError(response.errorBody()?.string()))
                }
            } catch (e: IOException) {
                ApiResult.Failure(ApiError.NetworkFailure(e))
            }
        }

    override suspend fun replaceGeofences(
        ifMatch: String,
        geofences: List<GeofenceDto>,
    ): ApiResult<ETagged<GeofenceConfigResponseDto>> = withAuthRetry {
        try {
            val response = service.replaceGeofences(ifMatch, ReplaceGeofencesRequestDto(geofences))
            if (response.isSuccessful) {
                val body = response.body()
                if (body == null) {
                    ApiResult.Failure(ApiError.InternalError("empty success body", null))
                } else {
                    val etag = response.headers()["ETag"].orEmpty()
                    ApiResult.Success(ETagged(body.data, etag), body.features.toDomain())
                }
            } else {
                ApiResult.Failure(parseError(response.errorBody()?.string()))
            }
        } catch (e: IOException) {
            ApiResult.Failure(ApiError.NetworkFailure(e))
        }
    }

    override suspend fun reportGeofenceEvents(
        deviceId: String,
        events: List<GeofenceEventInputDto>,
    ): ApiResult<GeofenceEventsResponseDto> =
        unwrap { service.reportGeofenceEvents(deviceId, ReportGeofenceEventsRequestDto(events)) }

    override suspend fun getGeofenceEventHistory(
        from: String,
        to: String,
        userId: String?,
        limit: Int?,
        cursor: String?,
    ): ApiResult<GeofenceEventHistoryResponseDto> =
        unwrap { service.getGeofenceEventHistory(from, to, userId, limit, cursor) }

    // ------------------------------------------------------------------
    // GroupsApi (001 §12; specs/005-temporary-groups.md)
    // ------------------------------------------------------------------

    override suspend fun createGroup(
        name: String,
        endsAt: String,
        expiryPolicy: String,
        displayName: String?,
    ): ApiResult<GroupDto> =
        unwrap { service.createGroup(CreateGroupRequestDto(name, endsAt, expiryPolicy, displayName)) }

    override suspend fun listGroups(): ApiResult<ListGroupsResponseDto> =
        unwrap { service.listGroups() }

    override suspend fun getGroup(groupId: String): ApiResult<GroupDetailDto> =
        unwrap { service.getGroup(groupId) }

    override suspend fun updateGroup(groupId: String, request: UpdateGroupRequestDto): ApiResult<GroupDto> =
        unwrap { service.updateGroup(groupId, request.requireAtLeastOneField()) }

    override suspend fun deleteGroup(groupId: String): ApiResult<Unit> =
        unwrapBare204 { service.deleteGroup(groupId) }

    override suspend fun joinGroup(code: String, displayName: String?): ApiResult<GroupDto> =
        unwrap { service.joinGroup(JoinGroupRequestDto(code, displayName)) }

    override suspend fun rotateGroupCode(groupId: String): ApiResult<RotateGroupCodeResponseDto> =
        unwrap { service.rotateGroupCode(groupId) }

    override suspend fun leaveGroup(groupId: String): ApiResult<Unit> =
        unwrapBare204 { service.leaveGroup(groupId) }

    override suspend fun removeGroupMember(groupId: String, userId: String): ApiResult<Unit> =
        unwrapBare204 { service.removeGroupMember(groupId, userId) }

    override suspend fun getGroupLatestLocations(groupId: String): ApiResult<GroupLatestLocationsResponseDto> =
        unwrap { service.getGroupLatestLocations(groupId) }
}
