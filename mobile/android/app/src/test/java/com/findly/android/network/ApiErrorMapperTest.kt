package com.findly.android.network

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Asserts every single code in 001-api-contract.md §10's catalog (27 codes — 21 original + the
 * 6 group-era additions from specs/005) maps to its own named [ApiError] subtype — never
 * [ApiError.Unknown] (specs/003-android-client.md §6.1, §16).
 */
class ApiErrorMapperTest {

    private fun map(code: String, details: JsonObject? = null) =
        ApiErrorMapper.fromCode(code, "debug message", details, "r_abc123")

    @Test
    fun `every catalog code maps to its named subtype, not Unknown`() {
        val expectations: Map<String, Class<out ApiError>> = mapOf(
            "AUTH_MISSING_TOKEN" to ApiError.AuthMissingToken::class.java,
            "AUTH_INVALID_TOKEN" to ApiError.AuthInvalidToken::class.java,
            "AUTH_TOKEN_EXPIRED" to ApiError.AuthTokenExpired::class.java,
            "AUTH_FORBIDDEN" to ApiError.AuthForbidden::class.java,
            "TRACKING_PAUSED" to ApiError.TrackingPaused::class.java,
            "PROFILE_NOT_FOUND" to ApiError.ProfileNotFound::class.java,
            "FAMILY_NOT_FOUND" to ApiError.FamilyNotFound::class.java,
            "MEMBER_NOT_FOUND" to ApiError.MemberNotFound::class.java,
            "DEVICE_NOT_FOUND" to ApiError.DeviceNotFound::class.java,
            "LOCATE_REQUEST_NOT_FOUND" to ApiError.LocateRequestNotFound::class.java,
            "GROUP_NOT_FOUND" to ApiError.GroupNotFound::class.java,
            "FAMILY_ALREADY_MEMBER" to ApiError.FamilyAlreadyMember::class.java,
            "GEOFENCE_VERSION_CONFLICT" to ApiError.GeofenceVersionConflict::class.java,
            "GROUP_ALREADY_MEMBER" to ApiError.GroupAlreadyMember::class.java,
            "GROUP_FULL" to ApiError.GroupFull::class.java,
            "INVITE_EXPIRED" to ApiError.InviteExpired::class.java,
            "LOCATE_REQUEST_EXPIRED" to ApiError.LocateRequestExpired::class.java,
            "GROUP_EXPIRED" to ApiError.GroupExpired::class.java,
            "INVITE_INVALID" to ApiError.InviteInvalid::class.java,
            "INVITE_ALREADY_USED" to ApiError.InviteAlreadyUsed::class.java,
            "GROUP_CODE_INVALID" to ApiError.GroupCodeInvalid::class.java,
            "VALIDATION_FAILED" to ApiError.ValidationFailed::class.java,
            "LOCATION_BATCH_TOO_LARGE" to ApiError.LocationBatchTooLarge::class.java,
            "LIMIT_EXCEEDED" to ApiError.LimitExceeded::class.java,
            "RATE_LIMITED" to ApiError.RateLimited::class.java,
            "INTERNAL_ERROR" to ApiError.InternalError::class.java,
            "PUSH_DELIVERY_FAILED" to ApiError.PushDeliveryFailed::class.java,
        )

        assertEquals("catalog has 27 codes (001 §10)", 27, expectations.size)

        expectations.forEach { (code, expectedClass) ->
            val mapped = map(code)
            assertTrue(
                "code $code should map to ${expectedClass.simpleName}, got ${mapped::class.java.simpleName}",
                expectedClass.isInstance(mapped),
            )
        }
    }

    @Test
    fun `unrecognized code maps to Unknown, preserving the code`() {
        val mapped = map("SOMETHING_NOT_IN_THE_CATALOG")
        assertTrue(mapped is ApiError.Unknown)
        assertEquals("SOMETHING_NOT_IN_THE_CATALOG", (mapped as ApiError.Unknown).code)
    }

    @Test
    fun `TRACKING_PAUSED decodes deviceSettings from details`() {
        val details = buildJsonObject {
            put("deviceSettings", buildJsonObject {
                put("syncIntervalMinutes", 30)
                put("trackingEnabled", JsonPrimitive(false))
            })
        }

        val mapped = map("TRACKING_PAUSED", details) as ApiError.TrackingPaused

        assertEquals(30, mapped.deviceSettings?.syncIntervalMinutes)
        assertEquals(false, mapped.deviceSettings?.trackingEnabled)
    }

    @Test
    fun `VALIDATION_FAILED decodes fields and reason from details`() {
        val details = buildJsonObject {
            put("fields", kotlinx.serialization.json.buildJsonArray {
                add(JsonPrimitive("fixes[3].recordedAt"))
            })
            put("reason", "beyondRetention")
        }

        val mapped = map("VALIDATION_FAILED", details) as ApiError.ValidationFailed

        assertEquals(listOf("fixes[3].recordedAt"), mapped.fields)
        assertEquals("beyondRetention", mapped.reason)
    }

    @Test
    fun `LIMIT_EXCEEDED decodes limit from details`() {
        val details = buildJsonObject { put("limit", "maxDevices") }

        val mapped = map("LIMIT_EXCEEDED", details) as ApiError.LimitExceeded

        assertEquals("maxDevices", mapped.limit)
    }

    @Test
    fun `GEOFENCE_VERSION_CONFLICT decodes currentEtag from details`() {
        val details = buildJsonObject { put("currentEtag", "\"0x8DC5F3A9B2C1D40\"") }

        val mapped = map("GEOFENCE_VERSION_CONFLICT", details) as ApiError.GeofenceVersionConflict

        assertEquals("\"0x8DC5F3A9B2C1D40\"", mapped.currentEtag)
    }

    @Test
    fun `RATE_LIMITED decodes retryAfterSeconds from details`() {
        val details = buildJsonObject { put("retryAfterSeconds", 30) }

        val mapped = map("RATE_LIMITED", details) as ApiError.RateLimited

        assertEquals(30, mapped.retryAfterSeconds)
    }

    @Test
    fun `LOCATION_BATCH_TOO_LARGE decodes max from details`() {
        val details = buildJsonObject { put("max", 100) }

        val mapped = map("LOCATION_BATCH_TOO_LARGE", details) as ApiError.LocationBatchTooLarge

        assertEquals(100, mapped.max)
    }

    @Test
    fun `GROUP_FULL decodes max from details`() {
        val details = buildJsonObject { put("max", 50) }

        val mapped = map("GROUP_FULL", details) as ApiError.GroupFull

        assertEquals(50, mapped.max)
    }

    @Test
    fun `GROUP_FULL missing details yields null max rather than throwing`() {
        val mapped = map("GROUP_FULL", details = null) as ApiError.GroupFull

        assertEquals(null, mapped.max)
    }

    @Test
    fun `missing details yields null typed fields rather than throwing`() {
        val mapped = map("VALIDATION_FAILED", details = null) as ApiError.ValidationFailed

        assertEquals(null, mapped.fields)
        assertEquals(null, mapped.reason)
    }
}
