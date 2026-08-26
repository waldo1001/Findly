package com.findly.android.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [ApiError.userMessage] must return a short, friendly, code-appropriate string — **never**
 * [ApiError.message] itself (001-api-contract.md §1.3: "debug text, never shown raw to users";
 * §10: "clients map `code` → localized UX"). Every case below is constructed with an obviously
 * server-debug-looking `message` to make sure it never leaks through.
 */
class ApiErrorUserMessageTest {

    private val rawServerMessage = "raw debug text from server, never shown to users"

    @Test
    fun `LIMIT_EXCEEDED maps to a plan-limit-specific friendly message, not the raw server message`() {
        val error = ApiError.LimitExceeded(limit = "maxGeofences", message = rawServerMessage, requestId = "r_1")

        val userMessage = error.userMessage()

        assertEquals("You've reached your geofence limit for this plan.", userMessage)
        assertNotEquals(rawServerMessage, userMessage)
    }

    @Test
    fun `LIMIT_EXCEEDED with exportsPerDay maps to a friendly retry-tomorrow message (specs 008)`() {
        val error = ApiError.LimitExceeded(limit = "exportsPerDay", message = rawServerMessage, requestId = "r_1")

        assertEquals("You've reached today's export limit — please try again tomorrow.", error.userMessage())
    }

    @Test
    fun `LIMIT_EXCEEDED with an unrecognized limit key still gets a generic friendly fallback`() {
        val error = ApiError.LimitExceeded(limit = "somethingNew", message = rawServerMessage, requestId = "r_1")

        assertEquals("You've reached your plan limit.", error.userMessage())
    }

    @Test
    fun `LIMIT_EXCEEDED maps the two group-era limit keys to friendly messages`() {
        assertEquals(
            "You've reached your active-group limit for this plan.",
            ApiError.LimitExceeded("maxActiveGroups", rawServerMessage, "r_1").userMessage(),
        )
        assertEquals(
            "That end date is further out than your plan allows.",
            ApiError.LimitExceeded("maxGroupDurationDays", rawServerMessage, "r_1").userMessage(),
        )
    }

    @Test
    fun `GEOFENCE_VERSION_CONFLICT maps to a friendly refreshing message`() {
        val error = ApiError.GeofenceVersionConflict(currentEtag = "\"3\"", message = rawServerMessage, requestId = "r_2")

        assertEquals("Someone else changed the geofences — refreshing.", error.userMessage())
    }

    @Test
    fun `AUTH_FORBIDDEN maps to a friendly permission message`() {
        val error = ApiError.AuthForbidden(message = rawServerMessage, requestId = "r_3")

        assertEquals("You don't have permission to do that.", error.userMessage())
    }

    @Test
    fun `VALIDATION_FAILED maps its reason to a distinct friendly message, falling back generically`() {
        assertEquals(
            "A family must always have at least one parent.",
            ApiError.ValidationFailed(null, "lastParent", rawServerMessage, "r_4").userMessage(),
        )
        assertEquals(
            "That date range is further back than your plan allows.",
            ApiError.ValidationFailed(null, "beyondRetention", rawServerMessage, "r_5").userMessage(),
        )
        assertEquals(
            "That device is already registered to another user.",
            ApiError.ValidationFailed(null, "deviceIdInUse", rawServerMessage, "r_6").userMessage(),
        )
        assertEquals(
            "As the group owner, you can't leave — end or delete the group instead.",
            ApiError.ValidationFailed(null, "ownerCannotLeave", rawServerMessage, "r_6b").userMessage(),
        )
        assertEquals(
            "Please check your entries and try again.",
            ApiError.ValidationFailed(listOf("fixes[0].recordedAt"), null, rawServerMessage, "r_7").userMessage(),
        )
    }

    @Test
    fun `the six group-era codes each get their own friendly message, not the raw server message`() {
        // specs/010-app-shell-and-screen-ux.md §2.1: "Please try again." is dropped — this is now
        // only the residual mutation-time fallback string (every *load* path routes to Onboarding
        // instead, per the §2.1 routing rule), and "try again" advised precisely the action
        // (retrying a GET/PATCH) that can never create a profile.
        assertEquals(
            "We couldn't find your profile.",
            ApiError.ProfileNotFound(rawServerMessage, "r_g1").userMessage(),
        )
        assertEquals(
            "That group couldn't be found.",
            ApiError.GroupNotFound(rawServerMessage, "r_g2").userMessage(),
        )
        assertEquals(
            "You're already part of that group.",
            ApiError.GroupAlreadyMember(rawServerMessage, "r_g3").userMessage(),
        )
        assertEquals(
            "That group is full.",
            ApiError.GroupFull(max = 50, message = rawServerMessage, requestId = "r_g4").userMessage(),
        )
        assertEquals(
            "This group has ended.",
            ApiError.GroupExpired(rawServerMessage, "r_g5").userMessage(),
        )
        assertEquals(
            "That group code isn't valid.",
            ApiError.GroupCodeInvalid(rawServerMessage, "r_g6").userMessage(),
        )
    }

    @Test
    fun `NetworkFailure maps to a connectivity message`() {
        val error = ApiError.NetworkFailure(java.io.IOException(rawServerMessage))

        assertEquals("Check your connection and try again.", error.userMessage())
    }

    @Test
    fun `an unrecognized (Unknown) code still gets a generic friendly message, never the raw code or text`() {
        val error = ApiError.Unknown(code = "SOME_FUTURE_CODE", message = rawServerMessage, requestId = "r_8")

        val userMessage = error.userMessage()

        assertEquals("Something went wrong. Please try again.", userMessage)
        assertNotEquals(rawServerMessage, userMessage)
    }

    @Test
    fun `every ApiError subtype maps to a non-blank user message`() {
        val requestId = "r_9"
        val subtypes: List<ApiError> = listOf(
            ApiError.AuthMissingToken(rawServerMessage, requestId),
            ApiError.AuthInvalidToken(rawServerMessage, requestId),
            ApiError.AuthTokenExpired(rawServerMessage, requestId),
            ApiError.AuthForbidden(rawServerMessage, requestId),
            ApiError.TrackingPaused(null, rawServerMessage, requestId),
            ApiError.ProfileNotFound(rawServerMessage, requestId),
            ApiError.FamilyNotFound(rawServerMessage, requestId),
            ApiError.MemberNotFound(rawServerMessage, requestId),
            ApiError.DeviceNotFound(rawServerMessage, requestId),
            ApiError.LocateRequestNotFound(rawServerMessage, requestId),
            ApiError.GroupNotFound(rawServerMessage, requestId),
            ApiError.FamilyAlreadyMember(rawServerMessage, requestId),
            ApiError.GeofenceVersionConflict(null, rawServerMessage, requestId),
            ApiError.GroupAlreadyMember(rawServerMessage, requestId),
            ApiError.GroupFull(null, rawServerMessage, requestId),
            ApiError.InviteExpired(rawServerMessage, requestId),
            ApiError.LocateRequestExpired(rawServerMessage, requestId),
            ApiError.GroupExpired(rawServerMessage, requestId),
            ApiError.InviteInvalid(rawServerMessage, requestId),
            ApiError.InviteAlreadyUsed(rawServerMessage, requestId),
            ApiError.GroupCodeInvalid(rawServerMessage, requestId),
            ApiError.ValidationFailed(null, null, rawServerMessage, requestId),
            ApiError.LocationBatchTooLarge(null, rawServerMessage, requestId),
            ApiError.LimitExceeded(null, rawServerMessage, requestId),
            ApiError.RateLimited(null, rawServerMessage, requestId),
            ApiError.InternalError(rawServerMessage, requestId),
            ApiError.PushDeliveryFailed(rawServerMessage, requestId),
            ApiError.Unknown("X", rawServerMessage, requestId),
            ApiError.NetworkFailure(java.io.IOException(rawServerMessage)),
        )

        subtypes.forEach { error ->
            val userMessage = error.userMessage()
            assertTrue("${error::class.simpleName} produced a blank user message", userMessage.isNotBlank())
            assertNotEquals(
                "${error::class.simpleName} leaked its raw server message",
                rawServerMessage,
                userMessage,
            )
        }
    }
}
