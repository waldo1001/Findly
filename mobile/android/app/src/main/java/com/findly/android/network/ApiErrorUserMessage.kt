package com.findly.android.network

/**
 * Maps every [ApiError] to a short, friendly, user-facing string — **never** [ApiError.message]
 * itself (001-api-contract.md §1.3: "`message`, debug text, never shown raw to users"; §10:
 * "clients map `code` → localized UX"). Mirrors the iOS client's
 * `Networking/APIError+UserMessage.swift`. Kept in one place so it's a single edit point for
 * future localization (today: hardcoded English, matching the rest of this client's literals,
 * e.g. `ui/home/HomeScreen.kt`).
 *
 * [ApiError.message] remains available for logs/debugging only — every `<Feature>StateHolder`
 * must render [userMessage] (via `FindlyErrorState`/`FindlyStatusChip`/etc.), never the raw field.
 */
fun ApiError.userMessage(): String = when (this) {
    is ApiError.AuthMissingToken,
    is ApiError.AuthInvalidToken,
    is ApiError.AuthTokenExpired,
    -> "Please sign in again."

    is ApiError.AuthForbidden -> "You don't have permission to do that."

    is ApiError.TrackingPaused -> "Location tracking is paused for this device."

    is ApiError.ProfileNotFound -> "We couldn't find your profile. Please try again."

    is ApiError.FamilyNotFound -> "We couldn't find your family. Please try again."

    is ApiError.MemberNotFound -> "That family member couldn't be found."

    is ApiError.DeviceNotFound -> "That device couldn't be found."

    is ApiError.LocateRequestNotFound -> "That locate request couldn't be found."

    is ApiError.GroupNotFound -> "That group couldn't be found."

    is ApiError.FamilyAlreadyMember -> "You're already part of a family."

    is ApiError.GeofenceVersionConflict -> "Someone else changed the geofences — refreshing."

    is ApiError.GroupAlreadyMember -> "You're already part of that group."

    is ApiError.GroupFull -> "That group is full."

    is ApiError.InviteExpired -> "This invite code has expired."

    is ApiError.LocateRequestExpired -> "This locate request has expired."

    is ApiError.GroupExpired -> "This group has ended."

    is ApiError.InviteInvalid -> "That invite code isn't valid."

    is ApiError.InviteAlreadyUsed -> "That invite code has already been used."

    is ApiError.GroupCodeInvalid -> "That group code isn't valid."

    is ApiError.ValidationFailed -> when (reason) {
        "lastParent" -> "A family must always have at least one parent."
        "beyondRetention" -> "That date range is further back than your plan allows."
        "deviceIdInUse" -> "That device is already registered to another user."
        "ownerCannotLeave" -> "As the group owner, you can't leave — end or delete the group instead."
        else -> "Please check your entries and try again."
    }

    is ApiError.LocationBatchTooLarge -> "Too many locations at once — please try again."

    is ApiError.LimitExceeded -> when (limit) {
        "maxDevices" -> "You've reached your device limit for this plan."
        "maxGeofences" -> "You've reached your geofence limit for this plan."
        "locateRequestsPerDay" -> "You've reached today's locate-request limit."
        "minSyncIntervalMinutes" -> "That sync interval isn't available on your plan."
        "maxActiveGroups" -> "You've reached your active-group limit for this plan."
        "maxGroupDurationDays" -> "That end date is further out than your plan allows."
        else -> "You've reached your plan limit."
    }

    is ApiError.RateLimited -> "Too many requests — please wait a moment and try again."

    is ApiError.InternalError -> "Something went wrong on our end. Please try again."

    is ApiError.PushDeliveryFailed -> "We couldn't send a notification for that."

    is ApiError.Unknown -> "Something went wrong. Please try again."

    is ApiError.NetworkFailure -> "Check your connection and try again."
}
