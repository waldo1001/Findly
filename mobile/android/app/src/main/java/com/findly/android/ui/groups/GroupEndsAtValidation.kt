package com.findly.android.ui.groups

private const val MIN_DURATION_MILLIS = 60L * 60 * 1000
private const val DAY_MILLIS = 24L * 60 * 60 * 1000

/**
 * The client-side mirror of the dated-`endsAt` rules in 001 §12.1/§12.4, shared by
 * [CreateGroupStateHolder] and [GroupDetailStateHolder] (005 §2.5 item 6): at least now + 1 h, and
 * at most now + [maxDays] when that plan limit is non-null (`null` = no cap). Returns a user-facing
 * message, or `null` if valid. The server stays authoritative.
 */
internal fun validateEndsAt(endsAtMillis: Long, nowMillis: Long, maxDays: Int?): String? = when {
    endsAtMillis < nowMillis + MIN_DURATION_MILLIS -> "End time must be at least 1 hour from now"
    maxDays != null && endsAtMillis > nowMillis + maxDays * DAY_MILLIS -> "That end date is further out than your plan allows"
    else -> null
}
