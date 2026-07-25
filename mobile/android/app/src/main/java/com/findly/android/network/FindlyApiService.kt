package com.findly.android.network

import com.findly.android.network.dto.AcceptInviteRequestDto
import com.findly.android.network.dto.AcceptInviteResponseDto
import com.findly.android.network.dto.CreateFamilyRequestDto
import com.findly.android.network.dto.CreateFamilyResponseDto
import com.findly.android.network.dto.CreateGroupRequestDto
import com.findly.android.network.dto.CreateInviteRequestDto
import com.findly.android.network.dto.CreateInviteResponseDto
import com.findly.android.network.dto.CreateLocateRequestRequestDto
import com.findly.android.network.dto.DeviceDto
import com.findly.android.network.dto.Envelope
import com.findly.android.network.dto.FamilyMeResponseDto
import com.findly.android.network.dto.FulfillLocateRequestRequestDto
import com.findly.android.network.dto.FulfillResponseDto
import com.findly.android.network.dto.GeofenceConfigResponseDto
import com.findly.android.network.dto.GeofenceEventHistoryResponseDto
import com.findly.android.network.dto.GeofenceEventsResponseDto
import com.findly.android.network.dto.GroupDetailDto
import com.findly.android.network.dto.GroupDto
import com.findly.android.network.dto.GroupLatestLocationsResponseDto
import com.findly.android.network.dto.JoinGroupRequestDto
import com.findly.android.network.dto.ListDevicesResponseDto
import com.findly.android.network.dto.ListGroupsResponseDto
import com.findly.android.network.dto.LocateRequestDto
import com.findly.android.network.dto.LocateRequestStatusResponseDto
import com.findly.android.network.dto.LocationHistoryResponseDto
import com.findly.android.network.dto.MemberDto
import com.findly.android.network.dto.RegisterDeviceRequestDto
import com.findly.android.network.dto.ReplaceGeofencesRequestDto
import com.findly.android.network.dto.ReportGeofenceEventsRequestDto
import com.findly.android.network.dto.ReportLocationsRequestDto
import com.findly.android.network.dto.ReportLocationsResponseDto
import com.findly.android.network.dto.RotateGroupCodeResponseDto
import com.findly.android.network.dto.UpdateDeviceRequestDto
import com.findly.android.network.dto.UpdateGroupRequestDto
import com.findly.android.network.dto.UpdateMemberRequestDto
import com.findly.android.network.dto.LatestLocationsResponseDto
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * Raw Retrofit surface — one method per 001-api-contract.md §3–§7/§12 endpoint, per the mapping
 * table in specs/003-android-client.md §5. Base URL ends in `/api/`; every path here is
 * `v1/...`, together forming 001 §1.1's `/api/v1/...` routes.
 *
 * Nothing outside [FindlyApiClient] depends on this interface directly — it implements the six
 * narrow port interfaces (`network/ports/`) that the rest of the app actually uses.
 */
interface FindlyApiService {

    // ---- §3 Family management ----

    @POST("v1/families")
    suspend fun createFamily(@Body request: CreateFamilyRequestDto): Response<Envelope<CreateFamilyResponseDto>>

    @GET("v1/families/me")
    suspend fun getMyFamily(): Response<Envelope<FamilyMeResponseDto>>

    @POST("v1/families/me/invites")
    suspend fun createInvite(@Body request: CreateInviteRequestDto): Response<Envelope<CreateInviteResponseDto>>

    @POST("v1/invites/accept")
    suspend fun acceptInvite(@Body request: AcceptInviteRequestDto): Response<Envelope<AcceptInviteResponseDto>>

    @PATCH("v1/families/me/members/{userId}")
    suspend fun updateMember(
        @Path("userId") userId: String,
        @Body request: UpdateMemberRequestDto,
    ): Response<Envelope<MemberDto>>

    /** Bare 204 (001 §3.6) — `ResponseBody` is Retrofit's built-in identity converter, so no JSON
     * parser is ever invoked on the intentionally empty body (specs/003 §6.3). */
    @DELETE("v1/families/me/members/{userId}")
    suspend fun removeMember(@Path("userId") userId: String): Response<ResponseBody>

    // ---- §4 Devices ----

    @POST("v1/devices")
    suspend fun registerDevice(@Body request: RegisterDeviceRequestDto): Response<Envelope<DeviceDto>>

    @GET("v1/devices")
    suspend fun listDevices(): Response<Envelope<ListDevicesResponseDto>>

    @PATCH("v1/devices/{deviceId}")
    suspend fun updateDevice(
        @Path("deviceId") deviceId: String,
        @Body request: UpdateDeviceRequestDto,
    ): Response<Envelope<DeviceDto>>

    // ---- §5 Location reporting & reading ----

    @POST("v1/locations")
    suspend fun reportLocations(
        @Header("X-Device-Id") deviceId: String,
        @Body request: ReportLocationsRequestDto,
    ): Response<Envelope<ReportLocationsResponseDto>>

    @GET("v1/locations/latest")
    suspend fun getLatestLocations(): Response<Envelope<LatestLocationsResponseDto>>

    @GET("v1/locations/history")
    suspend fun getLocationHistory(
        @Query("userId") userId: String,
        @Query("from") from: String,
        @Query("to") to: String,
        @Query("deviceId") deviceId: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("cursor") cursor: String? = null,
    ): Response<Envelope<LocationHistoryResponseDto>>

    // ---- §6 Push-to-locate ----

    @POST("v1/locate-requests")
    suspend fun createLocateRequest(
        @Body request: CreateLocateRequestRequestDto,
    ): Response<Envelope<LocateRequestDto>>

    @GET("v1/locate-requests/{requestId}")
    suspend fun getLocateRequest(
        @Path("requestId") requestId: String,
    ): Response<Envelope<LocateRequestStatusResponseDto>>

    @POST("v1/locate-requests/{requestId}/fulfill")
    suspend fun fulfillLocateRequest(
        @Path("requestId") requestId: String,
        @Header("X-Device-Id") deviceId: String,
        @Body request: FulfillLocateRequestRequestDto,
    ): Response<Envelope<FulfillResponseDto>>

    // ---- §7 Geofences ----

    /** A `304` is not `isSuccessful` (only 200–299 counts) — handled as a first-class branch in
     * [FindlyApiClient] before generic error handling (specs/003 §6.3). */
    @GET("v1/geofences")
    suspend fun getGeofences(
        @Header("If-None-Match") ifNoneMatch: String? = null,
    ): Response<Envelope<GeofenceConfigResponseDto>>

    @PUT("v1/geofences")
    suspend fun replaceGeofences(
        @Header("If-Match") ifMatch: String,
        @Body request: ReplaceGeofencesRequestDto,
    ): Response<Envelope<GeofenceConfigResponseDto>>

    @POST("v1/geofence-events")
    suspend fun reportGeofenceEvents(
        @Header("X-Device-Id") deviceId: String,
        @Body request: ReportGeofenceEventsRequestDto,
    ): Response<Envelope<GeofenceEventsResponseDto>>

    @GET("v1/geofence-events")
    suspend fun getGeofenceEventHistory(
        @Query("from") from: String,
        @Query("to") to: String,
        @Query("userId") userId: String? = null,
        @Query("limit") limit: Int? = null,
        @Query("cursor") cursor: String? = null,
    ): Response<Envelope<GeofenceEventHistoryResponseDto>>

    // ---- §12 Groups (temporary; specs/005) ----

    @POST("v1/groups")
    suspend fun createGroup(@Body request: CreateGroupRequestDto): Response<Envelope<GroupDto>>

    @GET("v1/groups")
    suspend fun listGroups(): Response<Envelope<ListGroupsResponseDto>>

    @GET("v1/groups/{groupId}")
    suspend fun getGroup(@Path("groupId") groupId: String): Response<Envelope<GroupDetailDto>>

    @PATCH("v1/groups/{groupId}")
    suspend fun updateGroup(
        @Path("groupId") groupId: String,
        @Body request: UpdateGroupRequestDto,
    ): Response<Envelope<GroupDto>>

    /** Bare 204 (001 §12.5) — see §3.6's `removeMember` doc for why this returns `ResponseBody`. */
    @DELETE("v1/groups/{groupId}")
    suspend fun deleteGroup(@Path("groupId") groupId: String): Response<ResponseBody>

    @POST("v1/groups/join")
    suspend fun joinGroup(@Body request: JoinGroupRequestDto): Response<Envelope<GroupDto>>

    @POST("v1/groups/{groupId}/code/rotate")
    suspend fun rotateGroupCode(@Path("groupId") groupId: String): Response<Envelope<RotateGroupCodeResponseDto>>

    /** Bare 204 (001 §12.8). */
    @POST("v1/groups/{groupId}/leave")
    suspend fun leaveGroup(@Path("groupId") groupId: String): Response<ResponseBody>

    /** Bare 204 (001 §12.9). */
    @DELETE("v1/groups/{groupId}/members/{userId}")
    suspend fun removeGroupMember(
        @Path("groupId") groupId: String,
        @Path("userId") userId: String,
    ): Response<ResponseBody>

    @GET("v1/groups/{groupId}/locations/latest")
    suspend fun getGroupLatestLocations(
        @Path("groupId") groupId: String,
    ): Response<Envelope<GroupLatestLocationsResponseDto>>

    // ---- §13 Privacy: export & deletion (specs/008-privacy-endpoints.md) ----

    /** The one unenveloped response in the API (001 §13.1) — `ResponseBody` is Retrofit's
     * built-in identity converter (same rationale as the bare-204 endpoints above), except here
     * the body is non-empty and is deliberately never run through the `Envelope<T>` JSON
     * converter (specs/003 §12.4). */
    @GET("v1/export")
    suspend fun exportData(@Query("userId") userId: String? = null): Response<ResponseBody>

    /** Bare 204 (001 §13.2) — permitted even without a profile (§1.5.3's idempotent no-op). */
    @DELETE("v1/users/me")
    suspend fun deleteAccount(): Response<ResponseBody>

    /** Bare 204 (001 §13.3, parent-only). */
    @DELETE("v1/families/me")
    suspend fun deleteFamily(): Response<ResponseBody>
}
