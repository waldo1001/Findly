package com.findly.android.network

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

/**
 * The single place a wire error `code` string is turned into a typed [ApiError]
 * (specs/003-android-client.md §6.1). Every one of the 27 codes in 001-api-contract.md §10 maps
 * to its own named subtype (21 original + the 6 group-era additions from specs/005:
 * `PROFILE_NOT_FOUND`, `GROUP_NOT_FOUND`, `GROUP_ALREADY_MEMBER`, `GROUP_FULL`, `GROUP_EXPIRED`,
 * `GROUP_CODE_INVALID`); anything else maps to [ApiError.Unknown] defensively.
 */
object ApiErrorMapper {

    fun fromCode(code: String, message: String, details: JsonObject?, requestId: String?): ApiError = when (code) {
        "AUTH_MISSING_TOKEN" -> ApiError.AuthMissingToken(message, requestId)
        "AUTH_INVALID_TOKEN" -> ApiError.AuthInvalidToken(message, requestId)
        "AUTH_TOKEN_EXPIRED" -> ApiError.AuthTokenExpired(message, requestId)
        "AUTH_FORBIDDEN" -> ApiError.AuthForbidden(message, requestId)
        "TRACKING_PAUSED" -> ApiError.TrackingPaused(deviceSettingsFrom(details), message, requestId)
        "PROFILE_NOT_FOUND" -> ApiError.ProfileNotFound(message, requestId)
        "FAMILY_NOT_FOUND" -> ApiError.FamilyNotFound(message, requestId)
        "MEMBER_NOT_FOUND" -> ApiError.MemberNotFound(message, requestId)
        "DEVICE_NOT_FOUND" -> ApiError.DeviceNotFound(message, requestId)
        "LOCATE_REQUEST_NOT_FOUND" -> ApiError.LocateRequestNotFound(message, requestId)
        "GROUP_NOT_FOUND" -> ApiError.GroupNotFound(message, requestId)
        "FAMILY_ALREADY_MEMBER" -> ApiError.FamilyAlreadyMember(message, requestId)
        "GEOFENCE_VERSION_CONFLICT" ->
            ApiError.GeofenceVersionConflict(stringField(details, "currentEtag"), message, requestId)
        "GROUP_ALREADY_MEMBER" -> ApiError.GroupAlreadyMember(message, requestId)
        "GROUP_FULL" -> ApiError.GroupFull(intField(details, "max"), message, requestId)
        "INVITE_EXPIRED" -> ApiError.InviteExpired(message, requestId)
        "LOCATE_REQUEST_EXPIRED" -> ApiError.LocateRequestExpired(message, requestId)
        "GROUP_EXPIRED" -> ApiError.GroupExpired(message, requestId)
        "INVITE_INVALID" -> ApiError.InviteInvalid(message, requestId)
        "INVITE_ALREADY_USED" -> ApiError.InviteAlreadyUsed(message, requestId)
        "GROUP_CODE_INVALID" -> ApiError.GroupCodeInvalid(message, requestId)
        "VALIDATION_FAILED" ->
            ApiError.ValidationFailed(fieldsList(details), stringField(details, "reason"), message, requestId)
        "LOCATION_BATCH_TOO_LARGE" -> ApiError.LocationBatchTooLarge(intField(details, "max"), message, requestId)
        "LIMIT_EXCEEDED" -> ApiError.LimitExceeded(stringField(details, "limit"), message, requestId)
        "RATE_LIMITED" -> ApiError.RateLimited(intField(details, "retryAfterSeconds"), message, requestId)
        "INTERNAL_ERROR" -> ApiError.InternalError(message, requestId)
        "PUSH_DELIVERY_FAILED" -> ApiError.PushDeliveryFailed(message, requestId)
        else -> ApiError.Unknown(code, message, requestId)
    }

    private fun stringField(details: JsonObject?, key: String): String? =
        details?.get(key)?.jsonPrimitive?.contentOrNull

    private fun intField(details: JsonObject?, key: String): Int? =
        details?.get(key)?.jsonPrimitive?.intOrNull

    private fun fieldsList(details: JsonObject?): List<String>? =
        details?.get("fields")?.jsonArray?.map { it.jsonPrimitive.content }

    private fun deviceSettingsFrom(details: JsonObject?): DeviceSettingsSnapshot? {
        val settings = details?.get("deviceSettings") as? JsonObject ?: return null
        val interval = settings["syncIntervalMinutes"]?.jsonPrimitive?.intOrNull ?: return null
        val enabled = settings["trackingEnabled"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() ?: return null
        return DeviceSettingsSnapshot(interval, enabled)
    }
}
